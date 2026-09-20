struct MockSentencePair {
    let english: String
    let german: String

    static let examples: [MockSentencePair] = [
        MockSentencePair(english: "I drink coffee every morning.", german: "Ich trinke jeden Morgen Kaffee."),
        MockSentencePair(english: "We can swim today.", german: "Wir können heute schwimmen."),
        MockSentencePair(english: "She buys a book.", german: "Sie kauft ein Buch."),
        MockSentencePair(english: "Tomorrow I will cook dinner.", german: "Morgen werde ich das Abendessen kochen."),
        MockSentencePair(
            english: "On Saturday, we take the bus to the park and go for a walk together.",
            german: "Am Samstag fahren wir mit dem Bus zum Park und gehen zusammen spazieren."
        )
    ]
}
