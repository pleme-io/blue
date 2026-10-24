use("deeta")

def outcome(text)
  ["ok", deeta::parse(text, :yaml, {documents: :all})]
rescue e
  ["error", to_s(reason_of(e)), e.message]
end

def reason_of(e)
  if e.data.nil?
    e.kind
  else
    deeta::get_or(e.data, :reason, e.kind)
  end
end
