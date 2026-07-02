import Foundation

struct Kartodromo: Identifiable, Hashable {
    let id = UUID()
    let nome: String
    let url: String
}

struct KartodromiData {
    static let lista: [Kartodromo] = [
        Kartodromo(nome: "Simulatore", url: "https://live.racefacer.com/simulator"),
        Kartodromo(nome: "Ottobiano Motorsport (Ottobiano, PV)", url: "https://live.racefacer.com/ottobianomotorsport"),        
        Kartodromo(nome: "Karting Club (Messina, ME)", url: "https://live.racefacer.com/kartodromomessina"),
        Kartodromo(nome: "Orlando Kart Center (Orlando, FL)", url: "https://live.racefacer.com/orlandokartcenter"),
        Kartodromo(nome: "Misanino (Misano Adriatico, RN)", url: "https://www.apex-timing.com/live-timing/misanino-kart/")
    ]
}
