# What `k8s:images` prints: one line per namespace, workload, container and
# image, sorted, under a header, in columns as wide as their widest value.
#
# Input (--slurp): `kubectl get pods -o json`, then `kubectl get
# replicasets,jobs -o json`.

def header: ["NAMESPACE", "WORKLOAD", "CONTAINER", "IMAGE"];
def column_gap: "  ";
def init_suffix: " (init)";

# The controller that owns an object, as "Kind/name"; null where nothing does.
def controller:
  first(.metadata.ownerReferences[]? | select(.controller) | "\(.kind)/\(.name)") // null;

# What names an object within its namespace.
def within($namespace): "\($namespace)\t\(.)";

# Of a listing: each controller that is owned in turn, to its own controller.
def parents:
  [ .items[]
    | controller as $up
    | select($up)
    | .metadata.namespace as $namespace
    | { key: ("\(.kind)/\(.metadata.name)" | within($namespace)), value: $up }
  ] | from_entries;

# The workload a pod is shown under: its controller followed up one step —
# a ReplicaSet's Deployment, a Job's CronJob — or the pod itself.
def workload($parents):
  .metadata.namespace as $namespace
  | (controller // "Pod/\(.metadata.name)") as $own
  | $parents[$own | within($namespace)] // $own;

# One row per container of every pod, init containers marked.
def rows($parents):
  .items[]
  | .metadata.namespace as $namespace
  | workload($parents) as $workload
  | (.spec.initContainers[]? | [$namespace, $workload, .name + init_suffix, .image]),
    (.spec.containers[]? | [$namespace, $workload, .name, .image]);

def pad($width): . + ((" " * ($width - length)) // "");

# Rows as lines: every column but the last padded to its widest cell.
def table:
  . as $rows
  | [ range($rows[0] | length) | . as $column | $rows | map(.[$column] | length) | max ] as $widths
  | $rows[]
  | . as $row
  | [ range(length) | . as $column
      | if $column < ($row | length) - 1 then $row[$column] | pad($widths[$column]) else $row[$column] end
    ]
  | join(column_gap);

. as [$pods, $owners]
| [header] + ([$pods | rows($owners | parents)] | unique) | table
