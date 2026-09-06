// OCR local via Apple Vision. Nada sai da máquina.
// uso: swift vision_ocr.swift <arquivo.pdf> <dir-saida> [dpi] [pagina...]
// Sem lista de páginas, roda o documento inteiro. Com, roda só as pedidas — é
// assim que o estágio 3 do pipeline (ADR-0025) trata UMA página sem reprocessar
// as outras.
import Foundation
import PDFKit
import Vision
import CoreGraphics

let args = CommandLine.arguments
guard args.count >= 3 else { FileHandle.standardError.write("uso: vision_ocr.swift <pdf> <dir-saida> [dpi]\n".data(using: .utf8)!); exit(2) }
let pdfPath = args[1]
let outDir = URL(fileURLWithPath: args[2], isDirectory: true)
let dpi = args.count > 3 ? Double(args[3])! : 300.0
let paginasPedidas = Set(args.dropFirst(4).compactMap { Int($0) })

guard let doc = PDFDocument(url: URL(fileURLWithPath: pdfPath)) else {
    FileHandle.standardError.write("não abriu o PDF\n".data(using: .utf8)!); exit(1)
}
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

struct Linha: Codable { let texto: String; let confianca: Float; let y: Double; let x: Double }
struct Pagina: Codable {
    let pagina: Int; let dpi: Double; let linhas: Int
    let confianca_media: Float; let confianca_min: Float
    let caracteres: Int; let texto: String
    let linhas_detalhe: [Linha]
}

var resumo: [[String: Any]] = []

for i in 0..<doc.pageCount {
    if !paginasPedidas.isEmpty && !paginasPedidas.contains(i + 1) { continue }
    guard let page = doc.page(at: i) else { continue }
    let box = page.bounds(for: .mediaBox)
    let scale = dpi / 72.0
    let w = Int((box.width * scale).rounded()), h = Int((box.height * scale).rounded())
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { continue }
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.scaleBy(x: scale, y: scale)
    ctx.translateBy(x: -box.origin.x, y: -box.origin.y)
    page.draw(with: .mediaBox, to: ctx)
    guard let img = ctx.makeImage() else { continue }

    let req = VNRecognizeTextRequest()
    req.recognitionLevel = .accurate
    req.usesLanguageCorrection = true
    req.recognitionLanguages = ["pt-BR", "pt-PT"]
    if #available(macOS 13.0, *) { req.revision = VNRecognizeTextRequestRevision3 }
    let handler = VNImageRequestHandler(cgImage: img, options: [:])
    try? handler.perform([req])
    let obs = (req.results ?? [])

    var linhas: [Linha] = []
    for o in obs {
        guard let top = o.topCandidates(1).first else { continue }
        let bb = o.boundingBox
        linhas.append(Linha(texto: top.string, confianca: top.confidence,
                            y: Double(1 - bb.midY), x: Double(bb.midX)))
    }
    // ordem de leitura: topo→base, esquerda→direita dentro da mesma faixa
    linhas.sort { a, b in abs(a.y - b.y) > 0.006 ? a.y < b.y : a.x < b.x }
    let texto = linhas.map { $0.texto }.joined(separator: "\n")
    let confs = linhas.map { $0.confianca }
    let p = Pagina(pagina: i + 1, dpi: dpi, linhas: linhas.count,
                   confianca_media: confs.isEmpty ? 0 : confs.reduce(0,+) / Float(confs.count),
                   confianca_min: confs.min() ?? 0,
                   caracteres: texto.count, texto: texto, linhas_detalhe: linhas)
    let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
    let data = try! enc.encode(p)
    try! data.write(to: outDir.appendingPathComponent(String(format: "pagina-%03d.json", i + 1)))
    resumo.append(["pagina": i + 1, "linhas": linhas.count, "caracteres": texto.count,
                   "confianca_media": Double(p.confianca_media), "confianca_min": Double(p.confianca_min)])
    print("p\(i+1): \(linhas.count) linhas, \(texto.count) chars, conf média \(String(format: "%.3f", p.confianca_media)), mín \(String(format: "%.3f", p.confianca_min))")
}
let rj = try! JSONSerialization.data(withJSONObject: resumo, options: [.prettyPrinted])
try! rj.write(to: outDir.appendingPathComponent("resumo.json"))
