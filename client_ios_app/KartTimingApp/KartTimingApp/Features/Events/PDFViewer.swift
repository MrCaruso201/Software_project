import SwiftUI
import PDFKit

struct PDFViewer: UIViewRepresentable {
    let pdfData: Data
    
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        if let doc = PDFDocument(data: pdfData) {
            pdfView.document = doc
        }
        return pdfView
    }
    
    func updateUIView(_ uiView: PDFView, context: Context) {
        if let doc = PDFDocument(data: pdfData) {
            uiView.document = doc
        }
    }
}
