package app.broomm.broomm

/** Only the inspected official Compose beta uses this newly verified launch contract. */
internal fun duckStationDocumentLaunch(code: Long, version: String?, signer: String): Boolean {
    if (code != 12126L) return false // Retain the existing route for other, unverified builds.
    require(version == "0.1-12693-gcc4a0d678" &&
        signer == "a6357957d296b3b03edeb62da317cb347ecde63b6577977ffcbfe0d9a6975450") {
        "This DuckStation build does not match the reviewed official beta. Nothing was launched."
    }
    return true
}

internal fun duckStationGamePath(authority: String, path: GameGrantPath): String {
    require(Regex("[a-zA-Z][a-zA-Z0-9_]*(\\.[a-zA-Z][a-zA-Z0-9_]*)+\\.games").matches(authority))
    val checked = gameGrantPath(listOf("document", path.documentId))
    return "/android_content/$authority/document@${checked.token}/${checked.relative.joinToString("/")}"
}
