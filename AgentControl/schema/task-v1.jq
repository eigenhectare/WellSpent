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

def safe_repo_path:
  nonempty_string
  and (startswith("/") | not)
  and (startswith("./") | not)
  and (test("(^|/)\\.\\.(/|$)") | not)
  and (endswith("/") | not);

def valid_task_id:
  type == "string" and test("^[A-Z][A-Z0-9]*(?:-[A-Z0-9]+)+$");

def valid_commit:
  type == "string" and test("^[0-9a-f]{40}$");

def valid_task($gates; $resources):
  . as $task
  | exact_object(
      ["schemaVersion", "taskId", "title", "type", "status", "risk", "outcome",
       "assignment", "base", "dependsOn", "scope", "writeScope", "acceptanceCriteria",
       "evidenceRequirements", "authorityRequirements", "legacyRefs", "blocker", "result"];
      ["schemaVersion", "taskId", "title", "type", "status", "risk", "outcome",
       "assignment", "base", "dependsOn", "scope", "writeScope", "acceptanceCriteria",
       "evidenceRequirements", "authorityRequirements", "legacyRefs", "blocker", "result"]
    )
  and (.schemaVersion == 1)
  and (.taskId | valid_task_id)
  and (.title | nonempty_string)
  and (.type | IN("feature", "bug", "spike", "chore", "release"))
  and (.status | IN("backlog", "ready", "in_progress", "in_review", "blocked", "done", "cancelled"))
  and (.risk | IN("low", "medium", "high", "critical"))
  and (.outcome | nonempty_string)
  and (
    .assignment == null or
    (.assignment | exact_object(["role", "id"]; ["role", "id"])
      and (.role | IN("coordinator", "implementer", "verifier", "integrator",
                      "release-steward", "monitor"))
      and (.id | nonempty_string))
  )
  and (if (.status | IN("in_progress", "in_review", "done")) then
         .assignment != null
       else true end)
  and (.base | exact_object(["branch", "commit"]; ["branch", "commit"]))
  and (.base.branch | nonempty_string)
  and (.base.commit | valid_commit)
  and (.dependsOn | unique_strings)
  and all(.dependsOn[]; valid_task_id)
  and ((.dependsOn | index($task.taskId)) == null)
  and (.scope | exact_object(["included", "excluded"]; ["included", "excluded"]))
  and (.scope.included | unique_strings and length > 0)
  and (.scope.excluded | unique_strings)
  and (.writeScope | exact_object(["paths", "resources"]; ["paths", "resources"]))
  and (.writeScope.paths | unique_strings)
  and all(.writeScope.paths[]; safe_repo_path)
  and (.writeScope.resources | unique_strings)
  and all(.writeScope.resources[]; . as $id | [$resources[].id] | index($id) != null)
  and (.writeScope.resources == (.writeScope.resources | sort))
  and all($resources[]; . as $resource |
    ([
      $task.writeScope.paths[] as $write_path
      | $resource.paths[] as $protected_path
      | ($write_path == $protected_path)
        or ($write_path | startswith($protected_path + "/"))
        or ($protected_path | startswith($write_path + "/"))
    ] | any) as $intersects
    | if $intersects then
        ($task.writeScope.resources | index($resource.id)) != null
      else true end)
  and (.acceptanceCriteria | type == "array" and length > 0)
  and all(.acceptanceCriteria[];
    exact_object(["id", "statement"]; ["id", "statement"])
    and (.id | type == "string" and test("^AC-[0-9]+$") )
    and (.statement | nonempty_string)
  )
  and (([.acceptanceCriteria[].id] | unique | length) == (.acceptanceCriteria | length))
  and (.evidenceRequirements | type == "array" and length > 0)
  and all(.evidenceRequirements[]; . as $requirement |
    exact_object(["id", "criterionIds", "evidenceClass", "gateIds", "candidateBound"];
                 ["id", "criterionIds", "evidenceClass", "gateIds", "candidateBound"])
    and (.id | type == "string" and test("^ER-[0-9]+$") )
    and (.criterionIds | unique_strings and length > 0)
    and all(.criterionIds[]; . as $id | [$task.acceptanceCriteria[].id] | index($id) != null)
    and (.evidenceClass | IN("source", "unit", "ui-simulator", "physical-device",
                             "signed-package", "external-service", "human-approval"))
    and (.gateIds | unique_strings and length > 0)
    and all(.gateIds[]; . as $id |
      any($gates[]; (.id == $id) and (.evidenceClass == $requirement.evidenceClass)))
    and all(.gateIds[]; . as $id |
      all($gates[] | select(.id == $id) | .resources[]; . as $resource |
        $task.writeScope.resources | index($resource) != null))
    and (.candidateBound | type == "boolean")
  )
  and (([.evidenceRequirements[].id] | unique | length) == (.evidenceRequirements | length))
  and (.authorityRequirements | unique_strings)
  and (.authorityRequirements == (.authorityRequirements | sort))
  and all(.authorityRequirements[];
    IN("repository-write", "device-mutate", "external-publish", "signing-upload",
       "app-store-submit", "public-release")
  )
  and (.legacyRefs | unique_strings)
  and all(.legacyRefs[]; safe_repo_path)
  and (
    if .status == "blocked" then
      (.blocker | exact_object(["kind", "owner", "reference", "resumeEvent"];
                               ["kind", "owner", "reference", "resumeEvent"])
        and (.kind | IN("dependency", "technical", "hardware", "authentication", "human-input", "external-state"))
        and (.owner | nonempty_string)
        and (.reference | nonempty_string)
        and (.resumeEvent | nonempty_string))
    else .blocker == null
    end
  )
  and (
    if .status == "done" then
      (.result | exact_object(["commit", "tree"]; ["commit", "tree"])
        and (.commit | valid_commit)
        and (.tree | valid_commit))
    else
      (.result == null or
        (.result | exact_object(["commit", "tree"]; ["commit", "tree"])
          and (.commit | valid_commit)
          and (.tree | valid_commit)))
    end
  );
