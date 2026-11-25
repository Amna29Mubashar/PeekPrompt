import Foundation
import Network
import Combine
import CoreImage
import CoreImage.CIFilterBuiltins
import AppKit

/// A tiny web server so you can control the prompter from your phone's browser
/// (same Wi-Fi). Every request must carry a random key, so other people on the
/// network can't take over.
final class RemoteServer: ObservableObject {
    static let shared = RemoteServer()

    @Published private(set) var isRunning = false
    @Published private(set) var address: URL?
    @Published private(set) var errorMessage: String?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "PeekPrompt.RemoteServer")
    private let preferredPort: UInt16 = 8765
    /// Changes every time the remote is turned on.
    private var key = RemoteServer.makeKey()

    private init() {}

    // MARK: Start / stop

    func start() {
        guard listener == nil else { return }
        key = RemoteServer.makeKey()
        errorMessage = nil
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: preferredPort) ?? .any)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async { self?.listenerChanged(state) }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            errorMessage = "Couldn't start the remote: \(error.localizedDescription)"
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        address = nil
    }

    private func listenerChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            isRunning = true
            let port = listener?.port?.rawValue ?? preferredPort
            if let ip = RemoteServer.localIPAddress() {
                address = URL(string: "http://\(ip):\(port)/?k=\(key)")
            } else {
                address = nil
                errorMessage = "Your Mac doesn't seem to be on a Wi-Fi or wired network."
            }
        case .failed(let error):
            errorMessage = "The remote stopped: \(error.localizedDescription)"
            stop()
        case .cancelled:
            isRunning = false
        default:
            break
        }
    }

    // MARK: HTTP

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }

            // Wait for the end of the request headers.
            if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self)
                self.respond(to: head, on: connection)
            } else if isComplete || error != nil || buffer.count > 16_384 {
                connection.cancel()
            } else {
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    private func respond(to head: String, on connection: NWConnection) {
        let requestLine = head.components(separatedBy: "\r\n").first ?? ""
        let parts = requestLine.split(separator: " ")
        let target = parts.count > 1 ? String(parts[1]) : "/"
        let components = URLComponents(string: "http://local" + target)
        let path = components?.path ?? "/"
        let query = Dictionary(
            (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { first, _ in first }
        )

        guard query["k"] == key else {
            send(status: "403 Forbidden", type: "text/plain", body: Data("This link has expired. Scan the new QR code in PeekPrompt's Settings.".utf8), on: connection)
            return
        }

        switch path {
        case "/":
            send(status: "200 OK", type: "text/html; charset=utf-8", body: Data(RemotePage.html.utf8), on: connection)
        case "/state":
            DispatchQueue.main.async {
                let body = RemoteServer.stateJSON()
                self.queue.async { self.send(status: "200 OK", type: "application/json", body: body, on: connection) }
            }
        case "/cmd":
            let command = query["c"] ?? ""
            DispatchQueue.main.async {
                RemoteServer.perform(command)
                let body = RemoteServer.stateJSON()
                self.queue.async { self.send(status: "200 OK", type: "application/json", body: body, on: connection) }
            }
        default:
            send(status: "404 Not Found", type: "text/plain", body: Data("Not found".utf8), on: connection)
        }
    }

    private func send(status: String, type: String, body: Data, on connection: NWConnection) {
        var response = Data("HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    // MARK: Commands & state (main thread)

    private static func perform(_ command: String) {
        let engine = ScrollEngine.shared
        let settings = PrompterSettings.shared
        switch command {
        case "toggle": engine.toggle()
        case "restart": engine.restart()
        case "faster": engine.changeSpeed(by: 5)
        case "slower": engine.changeSpeed(by: -5)
        case "back": engine.nudge(by: -60)
        case "forward": engine.nudge(by: 60)
        case "mute": MicrophoneMonitor.shared.isMuted.toggle()
        case "next": engine.nextSegment()
        case "prev": engine.previousSegment()
        case "show": settings.isPrompterVisible.toggle()
        case "mode":
            let all = ScrollMode.allCases
            let index = all.firstIndex(of: settings.mode) ?? 0
            settings.mode = all[(index + 1) % all.count]
        default: break
        }
    }

    private static func stateJSON() -> Data {
        let engine = ScrollEngine.shared
        let settings = PrompterSettings.shared
        let state: [String: Any] = [
            "playing": engine.isRunning,
            "progress": engine.progress,
            "elapsed": engine.elapsed,
            "speed": Int(settings.speed),
            "mode": settings.mode.title,
            "muted": MicrophoneMonitor.shared.isMuted,
            "usesMic": settings.mode.usesMicrophone,
            "visible": settings.isPrompterVisible,
            "script": settings.currentTitle,
            "segment": engine.segmentLabel ?? ""
        ]
        return (try? JSONSerialization.data(withJSONObject: state)) ?? Data("{}".utf8)
    }

    // MARK: Helpers

    private static func makeKey() -> String {
        let letters = Array("abcdefghjkmnpqrstuvwxyz23456789")
        return String((0..<10).map { _ in letters.randomElement()! })
    }

    /// The Mac's IPv4 address on Wi-Fi or Ethernet.
    static func localIPAddress() -> String? {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return nil }
        defer { freeifaddrs(pointer) }

        var candidates: [(name: String, ip: String)] = []
        for item in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(item.pointee.ifa_flags)
            guard let addr = item.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            candidates.append((String(cString: item.pointee.ifa_name), String(cString: host)))
        }
        // Prefer Wi-Fi / Ethernet (en0, en1…) over VPNs and virtual interfaces.
        return (candidates.first { $0.name.hasPrefix("en") } ?? candidates.first)?.ip
    }

    /// A QR code image for the remote link.
    static func qrCode(for url: URL, size: CGFloat = 180) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = size / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}

/// The page your phone shows. Plain HTML + a little JavaScript, no internet needed.
enum RemotePage {
    static let html = """
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <title>PeekPrompt Remote</title>
    <style>
      :root { color-scheme: dark; }
      * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
      body { margin: 0; font-family: -apple-system, system-ui, sans-serif; background: #0b0b0f; color: #f2f2f7;
             min-height: 100vh; display: flex; flex-direction: column; padding: max(20px, env(safe-area-inset-top)) 20px 28px; }
      header { text-align: center; margin-bottom: 18px; }
      h1 { font-size: 17px; margin: 0; font-weight: 600; }
      #meta { font-size: 13px; color: #8e8e93; margin-top: 4px; }
      .bar { height: 6px; background: #2c2c2e; border-radius: 3px; overflow: hidden; margin: 14px 0 22px; }
      .bar div { height: 100%; width: 0; background: linear-gradient(90deg, #64d2ff, #bf5af2, #ff375f); transition: width .4s; }
      .grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; }
      button { border: 0; border-radius: 18px; background: #1c1c1e; color: #f2f2f7; font-size: 15px; font-weight: 600;
               padding: 20px 6px; display: flex; flex-direction: column; align-items: center; gap: 6px; }
      button:active { transform: scale(.96); background: #2c2c2e; }
      button .i { font-size: 26px; line-height: 1; }
      #play { grid-column: 1 / -1; padding: 30px; font-size: 20px; background: linear-gradient(135deg, #5e5ce6, #bf5af2); }
      #play .i { font-size: 40px; }
      .muted { background: #3a1010 !important; color: #ff6961; }
      #err { color: #ff6961; text-align: center; font-size: 13px; margin-top: 14px; min-height: 1em; }
    </style>
    </head>
    <body>
      <header>
        <h1 id="script">PeekPrompt</h1>
        <div id="meta">Connecting…</div>
      </header>
      <div class="bar"><div id="progress"></div></div>
      <div class="grid">
        <button id="play" onclick="cmd('toggle')"><span class="i" id="playIcon">▶︎</span><span id="playText">Play</span></button>
        <button onclick="cmd('back')"><span class="i">⤒</span>Back</button>
        <button onclick="cmd('restart')"><span class="i">⏮</span>Restart</button>
        <button onclick="cmd('forward')"><span class="i">⤓</span>Ahead</button>
        <button onclick="cmd('slower')"><span class="i">−</span>Slower</button>
        <button onclick="cmd('mode')"><span class="i">⇄</span>Mode</button>
        <button onclick="cmd('faster')"><span class="i">+</span>Faster</button>
        <button id="mute" onclick="cmd('mute')"><span class="i">🎙</span><span id="muteText">Mute</span></button>
        <button onclick="cmd('show')"><span class="i">👁</span><span id="showText">Hide</span></button>
        <button onclick="location.reload()"><span class="i">↻</span>Refresh</button>
      </div>
      <div class="grid" id="slides" style="grid-template-columns: 1fr 1fr; margin-top: 12px; display: none">
        <button onclick="cmd('prev')"><span class="i">‹</span>Previous</button>
        <button onclick="cmd('next')"><span class="i">›</span>Next</button>
      </div>
      <div id="err"></div>
    <script>
      const key = new URLSearchParams(location.search).get('k');
      const $ = id => document.getElementById(id);
      function fmt(s) { s = Math.floor(s); return Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0'); }
      function render(s) {
        $('script').textContent = s.script + (s.segment ? ' · ' + s.segment : '');
        $('slides').style.display = s.segment ? 'grid' : 'none';
        $('meta').textContent = s.mode + ' · ' + (s.usesMic ? 'voice' : s.speed + ' speed') + ' · ' + fmt(s.elapsed);
        $('progress').style.width = Math.round(s.progress * 100) + '%';
        $('playIcon').textContent = s.playing ? '❚❚' : '▶︎';
        $('playText').textContent = s.playing ? 'Pause' : (s.usesMic ? 'Start listening' : 'Play');
        $('mute').classList.toggle('muted', s.muted);
        $('muteText').textContent = s.muted ? 'Unmute' : 'Mute';
        $('showText').textContent = s.visible ? 'Hide' : 'Show';
        $('err').textContent = '';
      }
      async function call(path) {
        try {
          const r = await fetch(path + (path.includes('?') ? '&' : '?') + 'k=' + key, { cache: 'no-store' });
          if (!r.ok) throw new Error(await r.text());
          render(await r.json());
        } catch (e) { $('err').textContent = 'Not connected. Is PeekPrompt still running on your Mac?'; }
      }
      function cmd(c) { if (navigator.vibrate) navigator.vibrate(10); call('/cmd?c=' + c); }
      call('/state');
      setInterval(() => call('/state'), 1000);
    </script>
    </body>
    </html>
    """
}
