import Foundation

struct Kartodromo: Identifiable, Hashable {
    let id = UUID()
    let nome: String
    let url: String
}

struct KartodromiData {
    static let lista: [Kartodromo] = [
        Kartodromo(nome: "Misanino (Misano Adriatico)", url: "https://live.racefacer.com/misanino"),
        Kartodromo(nome: "Mugellino (Scarperia)", url: "https://live.racefacer.com/mugellino"),
        Kartodromo(nome: "South Garda Karting (Lonato)", url: "https://live.racefacer.com/southgarda"),
        Kartodromo(nome: "VKI (Vicenza)", url: "https://live.racefacer.com/vki"),
        Kartodromo(nome: "Ottobiano", url: "https://live.racefacer.com/ottobianomotorsport"),
        Kartodromo(nome: "Simulatore gas", url: "https://live.racefacer.com/simulator"),
        Kartodromo(nome: "Hollywood Kart (Milano)", url: "https://live.racefacer.com/hollywoodkart")
    ]
}
