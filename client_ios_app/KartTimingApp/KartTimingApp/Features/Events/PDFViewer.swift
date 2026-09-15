import SwiftUI

/// Publishes a PDF on the server and opens its temporary URL in the browser.
@MainActor
enum PDFBrowser {
    static func open(data: Data, serverURL: URL?, token: String?) async throws {
        guard let serverURL, let token, !token.isEmpty else {
            throw NSError(domain: "PDFBrowser", code: 1, userInfo: [NSLocalizedDescriptionKey: "Server o sessione non disponibile."])
        }
        var request = URLRequest(url: serverURL.appendingPathComponent("documents/pdf"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/pdf", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "PDFBrowser", code: 2, userInfo: [NSLocalizedDescriptionKey: "Impossibile preparare il PDF sul server."])
        }
        struct DocumentLink: Decodable { let path: String }
        let link = try JSONDecoder().decode(DocumentLink.self, from: responseData)
        let opened = await UIApplication.shared.open(serverURL.appendingPathComponent(link.path))
        if !opened {
            throw NSError(domain: "PDFBrowser", code: 3, userInfo: [NSLocalizedDescriptionKey: "Impossibile aprire il browser."])
        }
    }
}
