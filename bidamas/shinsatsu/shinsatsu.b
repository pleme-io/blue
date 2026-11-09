@moduledoc """
shinsatsu (診察) — the credential doctor: a provider, the failure classes its credential helper can show, and for each class a diagnosis, the remediation steps and a verify step. A new provider or a new failure class is a declaration.

A host hands `diagnose` the facts of one failed connect: the credential helper's program and arguments, the error text, the cluster, the apiserver and the registry target. It returns one plain record a terminal can draw and a runner can execute. Each step names its flow: `:plain` runs and ends, `:device` prints a URL and a code to enter on another device, `:browser` opens a browser and waits. `prompt_of` reads the URL and the code from what a step printed. Nothing here runs a command.

    diagnose({program: "kubelogin", args: [], message: "AADSTS50173: grant revoked"})[:class] #=> "grant_revoked"
    incomplete #=> []
"""

use("hikisuu", [:flag])
use("moji", %i[includes lower made_of starts_with strip_suffix words])
use("retsu", %i[drop_n find_first index_of is_empty size])

legacy_names("0.1.1", [%w[flag hikisuu::flag]])

@doc """
failure: one failure class: the error markers that identify it, a short title, the diagnosis and the remediation.

    failure(:x, ["boom"], "Boom", "It broke.", fn(_f) [] end)[:title] #=> "Boom"
"""
def failure(name, markers, title, diagnosis, steps)
  {name:, markers:, title:, diagnosis:, steps:}
end

@doc """
provider: one credential provider: the helper programs it owns, the facts it reads from their arguments, and its failure classes in match order.

    provider(:p, "P", ["p"], fn(_f) [] end, [])[:label] #=> "P"
"""
def provider(name, label, programs, facts, failures)
  {name:, label:, programs:, facts:, failures:}
end

@doc """
known: the labelled facts whose value is present, as {label:, value:} records.

    known([["a", 1], ["b", nil]]) #=> [{label: "a", value: 1}]
"""
def known(pairs)
  map((p) -> {label: p[0], value: p[1]}, filter((p) -> p[1] != nil, pairs))
end

@doc """
azure_facts: what kubelogin's arguments say about the login: tenant, server id, login mode, client id.

    azure_facts({args: %w[--server-id s]}) #=> [{label: "server id", value: "s"}]
"""
def azure_facts(f)
  args = f[:args]
  known(
    [
      ["tenant", flag(args, "--tenant-id")],
      ["server id", flag(args, "--server-id")],
      ["login mode", flag(args, "--login")],
      ["client id", flag(args, "--client-id")]
    ]
  )
end

@doc """
step: one remediation command and its flow.

    step(%w[az logout], :plain)[:flow] #=> :plain
"""
def step(argv, flow)
  {argv:, flow:}
end

@doc """
azure_login: sign out, then sign in by device code to the tenant and the server id's scope.

    size(azure_login({args: []})) #=> 2
"""
def azure_login(f)
  args = f[:args]
  tenant = flag(args, "--tenant-id")
  scope = flag(args, "--server-id")
  login = append(%w[az login --use-device-code], with_flag("--tenant", tenant))
  login = append(login, with_flag("--scope", scoped(scope)))
  [step(%w[az logout], :plain), step(login, :device)]
end

@doc """
with_flag: a flag and its value, or nothing when the value is absent.

    with_flag("--tenant", nil) #=> []
"""
def with_flag(name, value)
  if value.nil?
    []
  else
    [name, value]
  end
end

@doc """
scoped: the `.default` scope of a server id, or nil.

    scoped("s") #=> "s/.default"
"""
def scoped(server_id)
  if server_id.nil?
    nil
  else
    "#{server_id}/.default"
  end
end

@doc """
or_else: the value, or the fallback when it is nil.

    or_else(nil, 3) #=> 3
"""
def or_else(value, fallback)
  if value.nil?
    fallback
  else
    value
  end
end

@doc """
aws_facts: what `aws eks get-token`'s arguments say: profile, region, cluster, role.

    aws_facts({args: %w[--profile ops]}) #=> [{label: "profile", value: "ops"}]
"""
def aws_facts(f)
  args = f[:args]
  known(
    [
      ["profile", flag(args, "--profile")],
      ["region", flag(args, "--region")],
      ["cluster", flag(args, "--cluster-name")],
      ["role", flag(args, "--role-arn")]
    ]
  )
end

@doc """
aws_login: an AWS SSO sign-in by device code, for the profile when one is named.

    aws_login({args: []})[0][:flow] #=> :device
"""
def aws_login(f)
  profile = flag(f[:args], "--profile")
  argv = append(
    %w[aws sso login --use-device-code],
    with_flag("--profile", profile)
  )
  [step(argv, :device)]
end

@doc """
gcp_login: a gcloud sign-in in the browser.

    gcp_login({})[0][:argv] #=> %w[gcloud auth login]
"""
def gcp_login(_f)
  [step(%w[gcloud auth login], :browser)]
end

@doc """
nerai_facts: the registry target a refusal points at.

    nerai_facts({target: "t"}) #=> [{label: "target", value: "t"}]
"""
def nerai_facts(f)
  known([["target", f[:target]]])
end

@doc """
none: no facts and no steps.

    none({}) #=> []
"""
def none(_f)
  []
end

@doc """
providers: every provider the doctor knows, each with its failure classes in match order.

    size(providers) #=> 4
"""
def providers()
  [
    provider(
      :azure,
      "Azure",
      %w[kubelogin az],
      azure_facts,
      [
        failure(
          :grant_revoked,
          %w[AADSTS50173 AADSTS50133 AADSTS50132 AADSTS50089],
          "Azure login expired",
          "Entra ID revoked the sign-in grant, for example after a password reset. Sign in again.",
          azure_login
        ),
        failure(
          :token_expired,
          [
            "AADSTS700082",
            "AADSTS70043",
            "AADSTS70008",
            "refresh token has expired"
          ],
          "Azure login expired",
          "The refresh token is past its lifetime. Sign in again.",
          azure_login
        ),
        failure(
          :wrong_tenant,
          %w[AADSTS50020 AADSTS90072 AADSTS700016 AADSTS90002],
          "Azure account is in the wrong tenant",
          "The signed-in account is not in the tenant that owns the cluster. Sign in to that tenant.",
          azure_login
        ),
        failure(
          :no_subscription,
          ["No subscriptions found", "no subscription"],
          "Azure account sees no subscription",
          "The account signed in, but it sees no subscription. Sign in with an account that has access.",
          azure_login
        ),
        failure(
          :not_logged_in,
          ["Please run 'az login'", "az login", "AzureCLICredential"],
          "Azure CLI is not signed in",
          "kubelogin asks the Azure CLI for a token, and the Azure CLI has no account. Sign in.",
          azure_login
        )
      ]
    ),
    provider(
      :aws,
      "AWS",
      %w[aws aws-iam-authenticator],
      aws_facts,
      [
        failure(
          :sso_expired,
          [
            "SSO session associated with this profile has expired",
            "Error when retrieving token from sso",
            "Token has expired and refresh failed",
            "token is expired"
          ],
          "AWS SSO session expired",
          "The AWS SSO session is past its lifetime. Sign in again.",
          aws_login
        ),
        failure(
          :no_credentials,
          [
            "Unable to locate credentials",
            "could not be found",
            "ExpiredToken"
          ],
          "AWS has no usable credentials",
          "The AWS CLI found no credentials for this profile. Sign in.",
          aws_login
        )
      ]
    ),
    provider(
      :gcp,
      "Google Cloud",
      %w[gke-gcloud-auth-plugin gcloud],
      none,
      [
        failure(
          :reauth,
          [
            "Reauthentication failed",
            "reauthentication",
            "invalid_grant",
            "gcloud auth login"
          ],
          "Google Cloud login expired",
          "The gcloud credential needs a new sign-in. Sign in again.",
          gcp_login
        ),
        failure(
          :no_adc,
          [
            "could not find default credentials",
            "Application Default Credentials"
          ],
          "Google Cloud has no default credentials",
          "No application default credential exists. Sign in.",
          fn(_f)
            [
              step(%w[gcloud auth login], :browser),
              step(%w[gcloud auth application-default login], :browser)
            ]
          end
        )
      ]
    ),
    provider(
      :nerai,
      "nerai",
      ["nerai-refuse"],
      nerai_facts,
      [
        failure(
          :refused,
          %w[nerai: refused],
          "Refused by the target registry",
          "The ambient kubeconfig refuses this name on purpose. Open the registry target, which carries its own kubeconfig.",
          none
        )
      ]
    )
  ]
end

@doc """
owns: whether a provider owns a credential helper program.

    owns({programs: ["aws"]}, "aws") #=> true
"""
def owns(p, program)
  index_of(p[:programs], program) >= 0
end

@doc """
matches: whether any marker of a failure class appears in the text, ignoring case.

    matches({markers: ["Boom"]}, "a boom here") #=> true
"""
def matches(c, text)
  low = lower(text)
  find_first((m) -> includes(low, lower(m)), c[:markers]) != nil
end

@doc """
verify_of: the credential helper itself, the step that proves a sign-in worked; nothing for a refusal.

    verify_of({program: "aws", args: ["x"]}) #=> ["aws", "x"]
"""
def verify_of(f)
  if f[:program].nil? or f[:program] == "" or f[:program] == "nerai-refuse"
    []
  else
    append([f[:program]], f[:args])
  end
end

@doc """
record: the plain record a host draws for one diagnosis.

    record({name: :p, label: "P", facts: none}, {name: :c, title: "T", diagnosis: "D", steps: none}, {args: []})[:class] #=> "c"
"""
def record(p, c, f)
  {
    provider: to_s(p[:name]),
    label: p[:label],
    class: to_s(c[:name]),
    title: c[:title],
    diagnosis: c[:diagnosis],
    facts: append(
      known([["cluster", f[:cluster]], ["apiserver", f[:server]]]),
      p[:facts](f)
    ),
    steps: c[:steps](f),
    verify: verify_of(f)
  }
end

@doc """
diagnose: the record for one failed connect, or nil when no class matches. `facts` takes {program:, args:, message:, cluster:, server:, target:}.

    diagnose({program: "aws", args: ["--profile", "p"], message: "Error when retrieving token from sso"})[:steps] #=> [{argv: %w[aws sso login --use-device-code --profile p], flow: :device}]
"""
def diagnose(facts)
  f = {
    program: or_else(facts[:program], ""),
    args: or_else(facts[:args], []),
    message: or_else(facts[:message], ""),
    cluster: facts[:cluster],
    server: facts[:server],
    target: facts[:target]
  }
  owned = filter((p) -> owns(p, f[:program]), providers)
  found = first_match(owned, f)
  if found.nil?
    first_match(providers, f)
  else
    found
  end
end

@doc """
first_match: the first diagnosis any provider of the pool gives, or nil.

    first_match([], {message: ""}) #=> nil
"""
def first_match(pool, f)
  reduce(
    fn(found, p)
      if found != nil
        found
      else
        c = find_first((c) -> matches(c, f[:message]), p[:failures])
        if c.nil?
          nil
        else
          record(p, c, f)
        end
      end
    end,
    nil,
    pool
  )
end

@doc """
classes: every failure class, as {provider:, class:} records.

    size(classes) > 0 #=> true
"""
def classes()
  reduce(
    fn(acc, p)
      append(
        acc,
        map(
          (c) -> {provider: to_s(p[:name]), class: to_s(c[:name])},
          p[:failures]
        )
      )
    end,
    [],
    providers
  )
end

@doc """
incomplete: every failure class that lacks a marker, a title, a diagnosis or a remediation. Remediation is a step, or the nerai answer to open the registry target.

    incomplete #=> []
"""
def incomplete()
  probe = {
    program: "x",
    args: [],
    message: "",
    cluster: nil,
    server: nil,
    target: "t"
  }
  reduce(
    fn(acc, p)
      append(
        acc,
        map(
          (c) -> "#{p[:name]}/#{c[:name]}",
          filter(
            fn(c)
              is_empty(c[:markers]) or
                c[:title] == "" or
                c[:diagnosis] == "" or
                is_empty(c[:steps](probe)) and p[:name] != :nerai
            end,
            p[:failures]
          )
        )
      )
    end,
    [],
    providers
  )
end

@doc """
diagnose_json: `diagnose` over JSON text, for a host that speaks JSON.

    diagnose_json("{}") #=> "null"
"""
def diagnose_json(text)
  json_write(diagnose(keyed(json_read(text))))
end

@doc """
keyed: the facts a host sent, read from a JSON map.

    keyed(json_read("{}"))[:program] #=> ""
"""
def keyed(m)
  {
    program: json_get_or(m, :program, ""),
    args: json_get_or(m, :args, []),
    message: json_get_or(m, :message, ""),
    cluster: json_get_or(m, :cluster, nil),
    server: json_get_or(m, :server, nil),
    target: json_get_or(m, :target, nil)
  }
end

@doc """
classes_json: `classes` as JSON text.

    json_read(classes_json)[0]["provider"] #=> "azure"
"""
def classes_json()
  json_write(classes)
end

@doc """
incomplete_json: `incomplete` as JSON text.

    incomplete_json #=> "[]"
"""
def incomplete_json()
  json_write(incomplete)
end

@doc """
url_like?: whether a word is an http or https URL.

    url_like?("https://x") #=> true
"""
def url_like?(w)
  starts_with(w, "https://") or starts_with(w, "http://")
end

@doc """
code_like?: whether a word looks like a device code: four or more capitals, digits or dashes.

    code_like?("ABCD-12") #=> true
"""
def code_like?(w)
  size(w) >= 4 and made_of(w, "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
end

@doc """
tokens: the words of a text without a trailing full stop or comma.

    tokens("open https://x.") #=> ["open", "https://x"]
"""
def tokens(text)
  map((w) -> strip_suffix(strip_suffix(w, "."), ","), words(text))
end

@doc """
prompt_of: the URL and the code a device or browser flow printed, each nil until it appears.

    prompt_of("To sign in, use a web browser to open the page https://microsoft.com/devicelogin and enter the code DXQ4KP7LM to authenticate.") #=> {code: "DXQ4KP7LM", url: "https://microsoft.com/devicelogin"}
    prompt_of("open the following URL:\n\nhttps://device.sso.us-east-1.amazonaws.com/\n\nThen enter the code:\n\nABCD-EFGH") #=> {code: "ABCD-EFGH", url: "https://device.sso.us-east-1.amazonaws.com/"}
    prompt_of("") #=> {code: nil, url: nil}
"""
def prompt_of(text)
  ws = tokens(text)
  at = index_of(map((w) -> lower(strip_suffix(w, ":")), ws), "code")
  after = if at < 0
    []
  else
    drop_n(ws, at + 1)
  end
  {url: find_first(url_like?, ws), code: find_first(code_like?, after)}
end

@doc """
prompt_json: `prompt_of` as JSON text.

    prompt_json("") #=> "{\"code\":null,\"url\":null}"
"""
def prompt_json(text)
  json_write(prompt_of(text))
end

test "the empty facts classify nothing"
  assert diagnose({}).nil?
  assert prompt_of("") == {url: nil, code: nil}
end

test "a revoked Azure grant signs out, then signs in by device code to the scope"
  d = diagnose(
    {
      program: "kubelogin",
      args: %w[get-token --server-id sid],
      message: "AADSTS50173: grant revoked",
      cluster: "east"
    }
  )
  assert d[:class] == "grant_revoked"
  assert d[:steps] ==
    [
      step(%w[az logout], :plain),
      step(%w[az login --use-device-code --scope sid/.default], :device)
    ]
  assert d[:verify] == %w[kubelogin get-token --server-id sid]
end

test "every class is complete, and the doctor answers in JSON a host can read back"
  assert incomplete == []
  assert get(
    json_read(
      diagnose_json("{\"program\": \"aws\", \"message\": \"Unable to locate credentials\"}")
    ),
    "class"
  ) == "no_credentials"
  assert json_read(classes_json)[0]["provider"] == "azure"
end

test "every remediation step of every class is an argv and a flow"
  probe = {
    program: "x",
    args: %w[--profile p --server-id s],
    message: "",
    target: "t"
  }
  steps = retsu::flat_map(
    providers,
    (p) -> retsu::flat_map(p[:failures], (c) -> c[:steps](probe))
  )
  assert size(steps) > 0
  assert filter(
    fn(st)
      not list?(st[:argv]) or not member?(st[:flow], %i[plain device browser])
    end,
    steps
  ) == []
end

test "an unknown failure stays unclassified"
  assert diagnose(
    {program: "kubelogin", message: "connection reset by peer"}
  ).nil?
end
