# Signing-generated keys are allowed explicitly; all app-owned capabilities
# must exactly match the source configuration. Profile authorization and final
# distribution re-signing remain separate checks, not inferred from this policy.
. as $actual
| ($source[0]) as $expected
| (keys - ($expected | keys) - ["application-identifier", "com.apple.developer.team-identifier",
    "get-task-allow", "keychain-access-groups", "beta-reports-active"]) == []
and all($expected | keys[]; . as $key | $actual[$key] == $expected[$key])
and .["com.apple.developer.team-identifier"] == $team
and (.["application-identifier"] | type == "string" and test("^[A-Z0-9]{10}\\.") and endswith("." + $bundle)
    and (contains("*") | not))
and ((has("get-task-allow") | not) or (.["get-task-allow"] | type == "boolean"))
and ((has("beta-reports-active") | not) or .["beta-reports-active"] == true)
and ((has("keychain-access-groups") | not)
    or .["keychain-access-groups"] == [.["application-identifier"]])
