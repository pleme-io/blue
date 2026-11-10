use("retsu", %i[first rest])
use("shisutemu", %i[status_of stderr_of stdout_of])

def sim_target()
  "aarch64-apple-ios-sim"
end

def bundle_id()
  "io.pleme.blue.example"
end

def out_dir()
  "target/blue-ios"
end

def app_dir()
  "#{out_dir}/Blue.app"
end

def info()
  {
    "CFBundleExecutable" => "blue-ios",
    "CFBundleIdentifier" => bundle_id,
    "CFBundleName" => "Blue",
    "CFBundleDisplayName" => "Blue",
    "CFBundlePackageType" => "APPL",
    "CFBundleShortVersionString" => "0.1.0",
    "CFBundleVersion" => "1",
    "CFBundleInfoDictionaryVersion" => "6.0",
    "MinimumOSVersion" => "17.0",
    "UIDeviceFamily" => [1, 2],
    "CFBundleSupportedPlatforms" => ["iPhoneSimulator"],
    "DTPlatformName" => "iphonesimulator",
    "UILaunchScreen" => {},
    "UIStatusBarHidden" => true,
    "UIViewControllerBasedStatusBarAppearance" => false,
    "CADisableMinimumFrameDurationOnPhone" => true,
    "UIApplicationSceneManifest" => {
      "UIApplicationSupportsMultipleScenes" => false,
      "UISceneConfigurations" => {
        "UIWindowSceneSessionRoleApplication" => [
          {
            "UISceneConfigurationName" => "Default Configuration",
            "UISceneDelegateClassName" => "BlueSceneDelegate"
          }
        ]
      }
    }
  }
end

def escape(s)
  replace(replace(replace(s, "&", "&amp;"), "<", "&lt;"), ">", "&gt;")
end

def plist_value(v)
  if v == true
    "<true/>"
  elsif v == false
    "<false/>"
  elsif integer?(v)
    "<integer>#{v}</integer>"
  elsif string?(v)
    "<string>#{escape(v)}</string>"
  elsif map?(v)
    body = map(
      (e) -> "<key>#{escape(first(e))}</key>#{plist_value(e[1])}",
      map_entries(v)
    )
    "<dict>#{join(body, "")}</dict>"
  else
    "<array>#{join(map(plist_value, v), "")}</array>"
  end
end

def plist(v)
  join(
    [
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
      "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">",
      "<plist version=\"1.0\">#{plist_value(v)}</plist>",
      ""
    ],
    line_break
  )
end

def must(step, cap)
  if status_of(cap) != 0
    raise(:red, "#{step}: #{stdout_of(cap)}#{stderr_of(cap)}")
  end
  cap
end

def ios_env()
  [
    ["LIBRARY_PATH", ""],
    %w[IPHONEOS_DEPLOYMENT_TARGET 17.0],
    %w[CC_aarch64_apple_ios_sim /usr/bin/clang],
    %w[CC_aarch64_apple_ios /usr/bin/clang],
    %w[CARGO_TARGET_AARCH64_APPLE_IOS_SIM_LINKER /usr/bin/clang],
    %w[CARGO_TARGET_AARCH64_APPLE_IOS_LINKER /usr/bin/clang]
  ]
end

def build(target)
  must(
    "cargo build #{target}",
    exec_with_env(
      ios_env,
      "cargo",
      "build",
      "-j",
      "4",
      "--target",
      target,
      "-p",
      "blue-lang-ios"
    )
  )
end

def bundle(program)
  must("clean", exec_capture("/bin/rm", "-rf", app_dir))
  mkdir_p(app_dir)
  must(
    "copy shell",
    exec_capture(
      "/bin/cp",
      "target/#{sim_target}/debug/blue-ios",
      "#{app_dir}/blue-ios"
    )
  )
  must("copy program", exec_capture("/bin/cp", program, "#{app_dir}/app.b"))
  write_file("#{app_dir}/Info.plist", plist(info))
  must(
    "codesign",
    exec_capture(
      "/usr/bin/codesign",
      "--force",
      "--sign",
      "-",
      "--timestamp=none",
      app_dir
    )
  )
end

def simctl(args)
  tool = split(getenv("BLUE_IOS_SIMCTL", "xcrun simctl"), " ")
  exec_capture(first(tool), *append(rest(tool), args))
end

def udid()
  id = getenv("BLUE_IOS_SIM_UDID")
  if id.nil?
    raise(:blind, "set BLUE_IOS_SIM_UDID to a booted simulator")
  end
  id
end

def deploy(settle)
  id = udid
  must("install", simctl(["install", id, app_dir]))
  must(
    "launch",
    simctl(["launch", "--terminate-running-process", id, bundle_id])
  )
  sleep(settle)
  must("screenshot", simctl(["io", id, "screenshot", "#{out_dir}/shot.png"]))
  data = trim(
    stdout_of(
      must(
        "app container",
        simctl(["get_app_container", id, bundle_id, "data"])
      )
    )
  )
  write_stdout(read_file("#{data}/Documents/blue-ios-console.txt"))
end

def golden()
  must(
    "golden diff",
    exec_with_env(
      [["BLUE_IOS_SHOT", "#{cwd}/#{out_dir}/shot.png"]],
      "cargo",
      "test",
      "-j",
      "4",
      "-p",
      "blue-lang-ios",
      "--test",
      "golden",
      "--",
      "--ignored"
    )
  )
end

def main()
  args = argv
  verb = first(args) or "run"
  program = args[1] or "crates/blue-lang-ios/example/app.b"
  case verb
  when "build"
    build(sim_target)
    build("aarch64-apple-ios")
  when "run"
    build(sim_target)
    bundle(program)
    deploy(4)
  when "golden"
    build(sim_target)
    bundle(program)
    deploy(4)
    golden
    write_stdout(unlines(["green: the frame matches the golden"]))
  else
    raise(:usage, "blue run sim.b -- build|run|golden [program.b]")
  end
  exit_with(0)
end

test "the plist renders nested dicts, arrays and escapes"
  doc = plist({"a" => [1, true], "b<" => {"c" => "x&y"}})
  assert contains?(
    doc,
    "<dict><key>a</key><array><integer>1</integer><true/></array><key>b&lt;</key><dict><key>c</key><string>x&amp;y</string></dict></dict>"
  )
end
