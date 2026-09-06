def exact_object($allowed; $required):
  . as $object
  | (type == "object")
    and ((keys_unsorted - $allowed) | length == 0)
    and all($required[]; . as $key | $object | has($key));

def nonempty_string:
  type == "string" and length > 0 and (test("[[:cntrl:]]") | not);

def unique_strings:
  type == "array"
  and all(.[]; nonempty_string)
  and ((unique | length) == length);

def safe_locator:
  nonempty_string
  and (startswith("/") | not)
  and (startswith("./") | not)
  and (test("(^|/)\\.\\.(/|$)") | not)
  and (test("^(file|ssh)://") | not);

def valid_commit:
  type == "string" and test("^[0-9a-f]{40}$");

def valid_evidence($gate_ids):
  exact_object(
    ["schemaVersion", "receiptId", "taskId", "requirementId", "evidenceClass",
     "result", "producerRole", "producerId", "observedAt", "source", "gate",
     "claims", "artifacts", "limitations", "authorityReference", "publicReleaseApproved"];
    ["schemaVersion", "receiptId", "taskId", "requirementId", "evidenceClass",
     "result", "producerRole", "producerId", "observedAt", "source", "gate",
     "claims", "artifacts", "limitations", "authorityReference", "publicReleaseApproved"]
  )
  and (.schemaVersion == 1)
  and (.receiptId | type == "string" and test("^[A-Z0-9]+(?:-[A-Z0-9]+)+$"))
  and (.taskId | type == "string" and test("^[A-Z][A-Z0-9]*(?:-[A-Z0-9]+)+$"))
  and (.requirementId | type == "string" and test("^ER-[0-9]+$"))
  and (.evidenceClass | IN("source", "unit", "ui-simulator", "physical-device",
                           "signed-package", "external-service", "human-approval"))
  and (.result | IN("passed", "failed", "blocked", "not_run"))
  and (.producerRole | IN("coordinator", "implementer", "verifier", "integrator",
                          "release-steward", "owner", "external-service", "monitor"))
  and (.producerId | nonempty_string)
  and (.observedAt | type == "string"
    and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(Z|[+-][0-9]{2}:[0-9]{2})$"))
  and (.source | exact_object(["commit", "tree", "clean", "version", "build"];
                              ["commit", "tree", "clean", "version", "build"])
    and (.commit | valid_commit)
    and (.tree | valid_commit)
    and (.clean | type == "boolean")
    and (.version == null or (.version | type == "string" and test("^[0-9]+\\.[0-9]+\\.[0-9]+$")))
    and (.build == null or (.build | type == "string" and test("^[0-9]+$"))))
  and (.gate | exact_object(["id", "exitCode"]; ["id", "exitCode"])
    and (.id | . as $id | $gate_ids | index($id) != null)
    and (.exitCode == null or (.exitCode | type == "number" and floor == .)))
  and (.claims | unique_strings and length > 0)
  and (.artifacts | type == "array")
  and all(.artifacts[];
    exact_object(["kind", "locator", "sha256"]; ["kind", "locator", "sha256"])
    and (.kind | IN("repository", "ci-artifact", "local-diagnostic", "external"))
    and (.locator | safe_locator)
    and (.sha256 == null or (.sha256 | type == "string" and test("^[0-9a-f]{64}$")))
  )
  and all(.artifacts[];
    if .kind == "ci-artifact" then .sha256 != null else true end)
  and (if .result == "passed" and (.evidenceClass | IN("physical-device", "signed-package")) then
         (.artifacts | length) > 0 and all(.artifacts[]; .sha256 != null)
       elif .result == "passed" and .evidenceClass == "external-service" then
         (.artifacts | length) > 0
       else true end)
  and (.limitations | unique_strings)
  and (
    .authorityReference == null or
    (.authorityReference | exact_object(["kind", "reference", "confirmedBy", "confirmedAt", "authorityIds"];
                                        ["kind", "reference", "confirmedBy", "confirmedAt", "authorityIds"])
      and (.kind | IN("user-message", "signed-record", "external-record"))
      and (.reference | nonempty_string)
      and (.confirmedBy | nonempty_string)
      and (.confirmedAt | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$"))
      and (.authorityIds | unique_strings and length > 0)
      and all(.authorityIds[];
        IN("repository-write", "device-mutate", "external-publish", "signing-upload",
           "app-store-submit", "public-release")))
  )
  and (.publicReleaseApproved | type == "boolean")
  and (if .result == "passed" then
         .source.clean == true
         and (if .gate.id == "owner-attestation" then
                .gate.exitCode == null
              else .gate.exitCode == 0 end)
       else true end)
  and (if .evidenceClass == "human-approval" then
         .producerRole == "owner" and .gate.id == "owner-attestation" and .authorityReference != null
       else true end)
  and (if .publicReleaseApproved then
         .evidenceClass == "human-approval" and .result == "passed" and .producerRole == "owner"
       else true end);
