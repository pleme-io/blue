use blue_lang_check::contracts::{kinds_of_parameter, parameters, Kind};
use blue_lang_runtime::docs::NAMES;

#[test]
fn every_kinded_parameter_refuses_the_kinds_it_does_not_name() {
    let mut accepted = Vec::new();
    let mut probes = 0;
    for doc in NAMES.iter().filter(|d| d.topic.kinded()) {
        if !doc.signature.starts_with(&format!("{}(", doc.name)) {
            continue;
        }
        let Some(params) = parameters(doc.signature) else {
            continue;
        };
        if params.iter().any(String::is_empty) {
            continue;
        }
        for (i, p) in params.iter().enumerate() {
            let Some(kinds) = kinds_of_parameter(p) else {
                continue;
            };
            for wrong in Kind::ALL.iter().filter(|k| !kinds.contains(k)) {
                let args: Vec<&str> = params
                    .iter()
                    .enumerate()
                    .map(|(j, q)| {
                        if j == i {
                            wrong.literal()
                        } else {
                            kinds_of_parameter(q).map_or("1", |ks| ks[0].literal())
                        }
                    })
                    .collect();
                let call = format!("{}({})", doc.name, args.join(", "));
                let src = format!(
                    "r = {call}\nif procedure?(r)\n  raise(:deferred, \"a function value\")\nend\n"
                );
                probes += 1;
                if blue_lang_runtime::pipeline::run(&src).is_ok() {
                    accepted.push(format!("{call} takes {} as `{p}`", wrong.word()));
                }
            }
        }
    }
    assert!(probes > 100, "only {probes} probes ran");
    assert!(
        accepted.is_empty(),
        "the runtime accepts what the signature's parameter name refuses; rename the parameter in docs.rs:\n{}",
        accepted.join("\n")
    );
}
