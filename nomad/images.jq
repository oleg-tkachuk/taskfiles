# What `nomad:images` prints: one line per task of every job, sorted, under a
# header, in columns as wide as their widest value.
#
# Input (--slurp): `nomad job inspect -json` of each job, one after another.

def header: ["NAMESPACE", "JOB", "VERSION", "STATUS", "TASK", "DRIVER", "IMAGE"];
def column_gap: "  ";
# The status of a job that was stopped and not yet purged: it is listed, and
# runs nothing.
def stopped: "stopped";
# The image of a driver that runs none: exec, raw_exec, java.
def no_image: "-";

def status: if .Stop then stopped else .Status end;

def image: (.Config.image // "") | if . == "" then no_image else . end;

# One row per task of every job, under the job's version and status.
def rows:
  .[]
  | [.Namespace, .ID, (.Version | tostring), status] as $job
  | .TaskGroups[]?
  | .Name as $group
  | .Tasks[]?
  | $job + ["\($group)/\(.Name)", .Driver, image];

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

[header] + ([rows] | sort) | table
