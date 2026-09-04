def valid_symbols:
    type == "array"
    and length > 0
    and (unique | length) == length
    and all(.[]; test("^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12} \\(arm64|arm64_32\\)$"));

if ($binarySymbols | valid_symbols) and ($dSYMIdentifiers | valid_symbols)
    and (($binarySymbols | sort) == ($dSYMIdentifiers | sort))
then {
    checked: true,
    identifiers: ($binarySymbols | sort | map(
        capture("^(?<uuid>[0-9A-F-]+) \\((?<architecture>[^)]+)\\)$")
    ))
}
else error("Binary and dSYM architecture/UUID sets must be valid and identical")
end
