public enum DefaultCategories {
    public static func list(for language: GameLanguage) -> [String] {
        switch language {
        case .ptBR:
            ["Nome", "Animal", "Fruta", "Cor", "CEP", "Objeto", "Marca", "Profissão",
             "Comida", "Filme/Série", "Parte do corpo", "Minha sogra é…"]
        case .en:
            ["Name", "Animal", "Fruit", "Color", "City", "Object", "Brand", "Job",
             "Food", "Movie/TV show", "Body part", "Things in a kitchen"]
        }
    }
}
