//! What would change if a rendered object were applied: a structural
//! comparison of the rendered object with the one a cluster holds.
//!
//! Only the paths the rendering states are compared. A live object also
//! carries what the API server defaulted (`strategy`, `dnsPolicy`, a
//! Service's `clusterIP`) and its `status`; those are not the commit's, and
//! applying the rendering leaves them as they are, so they are not reported.
//! A list whose elements are objects with a `name` is matched by name, the
//! way Kubernetes merges containers, ports and env; any other list by
//! position.
//!
//! Values compare as JSON. A quantity the API server rewrote (`0.5` read
//! back as `500m`) reads as a change; that is a false positive this
//! comparison accepts rather than a second quantity parser.

use serde_json::Value;

/// One difference, at a path such as `spec.template.spec.containers[name=hello].image`.
#[derive(Clone, Debug, PartialEq)]
pub enum Change {
    /// The cluster holds `live` where the rendering states `desired`.
    Changed {
        path: String,
        live: Value,
        desired: Value,
    },
    /// The rendering states a value the cluster's object does not have.
    Missing { path: String, desired: Value },
}

impl std::fmt::Display for Change {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Change::Changed {
                path,
                live,
                desired,
            } => write!(f, "~ {path}: {live} -> {desired}"),
            Change::Missing { path, desired } => write!(f, "+ {path}: {desired}"),
        }
    }
}

/// Every path where `live` differs from `desired`, in the rendering's order.
#[must_use]
pub fn diff(desired: &Value, live: &Value) -> Vec<Change> {
    let mut changes = Vec::new();
    walk(&mut Vec::new(), desired, live, &mut changes);
    changes
}

fn walk(path: &mut Vec<String>, desired: &Value, live: &Value, out: &mut Vec<Change>) {
    match (desired, live) {
        (Value::Object(want), Value::Object(have)) => {
            for (k, v) in want {
                path.push(k.clone());
                match have.get(k) {
                    Some(h) => walk(path, v, h, out),
                    None => out.push(Change::Missing {
                        path: render_path(path),
                        desired: v.clone(),
                    }),
                }
                path.pop();
            }
        }
        (Value::Array(want), Value::Array(have)) if want.iter().all(named) => {
            for item in want {
                let name = item.get("name").and_then(Value::as_str).unwrap_or_default();
                path.push(["[name=", name, "]"].concat());
                match have.iter().find(|h| h.get("name") == item.get("name")) {
                    Some(h) => walk(path, item, h, out),
                    None => out.push(Change::Missing {
                        path: render_path(path),
                        desired: item.clone(),
                    }),
                }
                path.pop();
            }
        }
        (Value::Array(want), Value::Array(have)) => {
            for (i, item) in want.iter().enumerate() {
                path.push(["[", &i.to_string(), "]"].concat());
                match have.get(i) {
                    Some(h) => walk(path, item, h, out),
                    None => out.push(Change::Missing {
                        path: render_path(path),
                        desired: item.clone(),
                    }),
                }
                path.pop();
            }
        }
        _ if desired == live => {}
        _ => out.push(Change::Changed {
            path: render_path(path),
            live: live.clone(),
            desired: desired.clone(),
        }),
    }
}

fn named(v: &Value) -> bool {
    v.get("name").is_some_and(Value::is_string)
}

fn render_path(segments: &[String]) -> String {
    let mut text = String::new();
    for s in segments {
        if !text.is_empty() && !s.starts_with('[') {
            text.push('.');
        }
        text.push_str(s);
    }
    text
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn identical_objects_have_no_changes() {
        let v = json!({"spec": {"replicas": 2, "x": [1, 2]}});
        assert_eq!(diff(&v, &v), vec![]);
    }

    /// The live object's defaulted fields and status are not the commit's,
    /// and must not read as changes.
    #[test]
    fn fields_only_the_cluster_holds_are_not_changes() {
        let desired = json!({"spec": {"replicas": 2}});
        let live =
            json!({"spec": {"replicas": 2, "strategy": {"type": "RollingUpdate"}}, "status": {}});
        assert_eq!(diff(&desired, &live), vec![]);
    }

    #[test]
    fn a_changed_scalar_and_a_missing_field_are_reported_with_their_paths() {
        let desired = json!({"spec": {"replicas": 3, "paused": false}});
        let live = json!({"spec": {"replicas": 2}});
        let mut changes = diff(&desired, &live);
        changes.sort_by_key(ToString::to_string);
        assert_eq!(
            changes,
            vec![
                Change::Missing {
                    path: "spec.paused".into(),
                    desired: json!(false)
                },
                Change::Changed {
                    path: "spec.replicas".into(),
                    live: json!(2),
                    desired: json!(3)
                },
            ]
        );
        assert_eq!(changes[1].to_string(), "~ spec.replicas: 2 -> 3");
    }

    /// Containers are matched by name, so a reordered live list is no change
    /// and a renamed container is a missing one.
    #[test]
    fn named_lists_match_by_name_not_position() {
        let desired = json!({"c": [{"name": "a", "image": "x:2"}, {"name": "b"}]});
        let live = json!({"c": [{"name": "b"}, {"name": "a", "image": "x:1"}]});
        assert_eq!(
            diff(&desired, &live),
            vec![Change::Changed {
                path: "c[name=a].image".into(),
                live: json!("x:1"),
                desired: json!("x:2")
            }]
        );
        let renamed = json!({"c": [{"name": "z"}]});
        assert!(matches!(
            diff(&renamed, &live).as_slice(),
            [Change::Missing { path, .. }] if path == "c[name=z]"
        ));
    }

    #[test]
    fn other_lists_match_by_position() {
        let desired = json!({"drop": ["ALL", "NET_RAW"]});
        let live = json!({"drop": ["ALL"]});
        assert_eq!(
            diff(&desired, &live),
            vec![Change::Missing {
                path: "drop[1]".into(),
                desired: json!("NET_RAW")
            }]
        );
    }
}
