@moduledoc """
burauza (ブラウザ) — the browser: what a blue page needs from the browser, generated.

`install` renders an installable app: its manifest, its service worker and the
tags that load them. `seam` names one row of the closed table of browser code a
page may run, and `loader` renders the rows a page asks for into its one
script. No project writes JavaScript: this file is the contained seam, until
blue runs in the page itself (`docs/FRONTEND-PLAN.md`, F8).

    size(seam_names) > 0 #=> true
"""

use("gamen", [:hex])
use("kyohi", [:raised])
use("moji", [:checked])
use("retsu", %i[find_first first size])

@doc """
install_seam: registers the service worker, and does nothing where a browser has none.

    contains?(install_seam, "'serviceWorker' in navigator") #=> true
"""
def install_seam()
  unlines(
    [
      "function install(){",
      "  if(!('serviceWorker' in navigator))return;",
      "  navigator.serviceWorker.register('/sw.js').catch(function(e){console.warn('no service worker',e);});",
      "}",
      "install();"
    ]
  )
end

@doc """
ink_seam: draws what a pointer traces on a canvas and sends the strokes when asked.

    contains?(ink_seam, "pointerdown") #=> true
"""
def ink_seam()
  unlines(
    [
      "function postJson(url,value){",
      "  return fetch(url,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(value)}).then(function(r){",
      "    if(!r.ok)return r.text().then(function(t){throw new Error(t);});",
      "    return r.json();",
      "  });",
      "}",
      "function say(text){",
      "  var at=document.querySelector('[data-seam=say]');",
      "  if(at)at.textContent=text;",
      "}",
      "function ink(canvas){",
      "  var o=JSON.parse(canvas.dataset.value);",
      "  var strokes=[];",
      "  var live=null;",
      "  var ctx=canvas.getContext('2d');",
      "  function size(){",
      "    var r=canvas.getBoundingClientRect();",
      "    var d=window.devicePixelRatio||1;",
      "    canvas.width=Math.round(r.width*d);",
      "    canvas.height=Math.round(r.height*d);",
      "    ctx.setTransform(d,0,0,d,0,0);",
      "    ctx.lineCap='round';",
      "    ctx.lineJoin='round';",
      "    ctx.lineWidth=o.line;",
      "    ctx.strokeStyle=getComputedStyle(canvas).color;",
      "    strokes.forEach(paint);",
      "  }",
      "  function paint(s){",
      "    ctx.beginPath();",
      "    ctx.moveTo(s[0][0],s[0][1]);",
      "    if(s.length===1)ctx.lineTo(s[0][0]+0.01,s[0][1]);",
      "    for(var i=1;i<s.length;i++){",
      "      var m=i<s.length-1?[(s[i][0]+s[i+1][0])/2,(s[i][1]+s[i+1][1])/2]:s[i];",
      "      ctx.quadraticCurveTo(s[i][0],s[i][1],m[0],m[1]);",
      "    }",
      "    ctx.stroke();",
      "  }",
      "  function point(e){",
      "    var r=canvas.getBoundingClientRect();",
      "    return [Math.round((e.clientX-r.left)*10)/10,Math.round((e.clientY-r.top)*10)/10];",
      "  }",
      "  function redraw(){",
      "    ctx.clearRect(0,0,canvas.width,canvas.height);",
      "    strokes.forEach(paint);",
      "  }",
      "  canvas.addEventListener('pointerdown',function(e){",
      "    e.preventDefault();",
      "    canvas.setPointerCapture(e.pointerId);",
      "    live=[point(e)];",
      "    strokes.push(live);",
      "    redraw();",
      "  });",
      "  canvas.addEventListener('pointermove',function(e){",
      "    if(!live)return;",
      "    var events=e.getCoalescedEvents?e.getCoalescedEvents():[e];",
      "    (events.length?events:[e]).forEach(function(c){live.push(point(c));});",
      "    redraw();",
      "  });",
      "  function end(){live=null;}",
      "  canvas.addEventListener('pointerup',end);",
      "  canvas.addEventListener('pointercancel',end);",
      "  document.querySelectorAll('[data-seam=ink-clear]').forEach(function(b){",
      "    b.addEventListener('click',function(){strokes=[];redraw();say('');});",
      "  });",
      "  document.querySelectorAll('[data-seam=ink-save]').forEach(function(b){",
      "    b.addEventListener('click',function(){",
      "      if(!strokes.length){say('Draw your signature first.');return;}",
      "      b.disabled=true;",
      "      var r=canvas.getBoundingClientRect();",
      "      postJson(o.post,{width:r.width,height:r.height,strokes:strokes}).then(function(a){location.assign(a.next);}).catch(function(e){b.disabled=false;say(e.message);});",
      "    });",
      "  });",
      "  window.addEventListener('resize',size);",
      "  size();",
      "}",
      "document.querySelectorAll('[data-seam=ink]').forEach(ink);"
    ]
  )
end

@doc """
upload_seam: sends a chosen or dropped file as the raw body of one request.

    contains?(upload_seam, "dataTransfer") #=> true
"""
def upload_seam()
  unlines(
    [
      "function send(o,file){",
      "  if(!file)return;",
      "  say('Reading '+file.name+'…');",
      "  fetch(o.post+'?name='+encodeURIComponent(file.name),{method:'POST',headers:{'Content-Type':'application/pdf'},body:file}).then(function(r){",
      "    if(!r.ok)return r.text().then(function(t){throw new Error(t);});",
      "    return r.json();",
      "  }).then(function(a){location.assign(a.next);}).catch(function(e){say(e.message);});",
      "}",
      "document.querySelectorAll('[data-seam=upload]').forEach(function(input){",
      "  var o=JSON.parse(input.dataset.value);",
      "  input.addEventListener('change',function(){send(o,input.files[0]);});",
      "  window.addEventListener('dragover',function(e){e.preventDefault();});",
      "  window.addEventListener('drop',function(e){",
      "    e.preventDefault();",
      "    send(o,e.dataTransfer.files[0]);",
      "  });",
      "});"
    ]
  )
end

@doc """
place_seam: places marks on a page, moves and sizes them, and sends them as fractions of the page.

    contains?(place_seam, "placements") #=> true
"""
def place_seam()
  unlines(
    [
      "function place(root){",
      "  var o=JSON.parse(root.dataset.value);",
      "  var finish=document.querySelector('[data-seam=finish]');",
      "  var marks=[];",
      "  function sync(){if(finish)finish.disabled=!marks.length;}",
      "  function add(page,x,y){",
      "    var w=o.width;",
      "    var m={page:page,x:Math.max(0,x-w/2),y:Math.max(0,y-w*o.aspect*page.clientWidth/page.clientHeight/2),w:w};",
      "    var at=document.createElement('div');",
      "    at.tabIndex=0;",
      "    at.setAttribute('role','group');",
      "    at.setAttribute('aria-label','Signature. Drag to move. Press Delete to remove.');",
      "    at.style.cssText='position:absolute;cursor:grab;outline:1px dashed currentColor;touch-action:none';",
      "    var img=document.createElement('img');",
      "    img.src=o.signature;",
      "    img.alt='';",
      "    img.draggable=false;",
      "    img.style.cssText='display:block;width:100%;height:auto;pointer-events:none';",
      "    var out=document.createElement('button');",
      "    out.type='button';",
      "    out.textContent='×';",
      "    out.setAttribute('aria-label','Remove this signature');",
      "    out.style.cssText='position:absolute;top:-0.8rem;right:-0.8rem;width:1.6rem;height:1.6rem;padding:0;border-radius:50%';",
      "    var grip=document.createElement('div');",
      "    grip.setAttribute('aria-hidden','true');",
      "    grip.style.cssText='position:absolute;right:-0.5rem;bottom:-0.5rem;width:1rem;height:1rem;border-radius:50%;background:currentColor;cursor:nwse-resize;touch-action:none';",
      "    at.append(img,out,grip);",
      "    function draw(){",
      "      at.style.left=m.x*100+'%';",
      "      at.style.top=m.y*100+'%';",
      "      at.style.width=m.w*100+'%';",
      "    }",
      "    function remove(){",
      "      at.remove();",
      "      marks=marks.filter(function(k){return k!==m;});",
      "      sync();",
      "    }",
      "    out.addEventListener('click',function(e){e.stopPropagation();remove();});",
      "    at.addEventListener('click',function(e){e.stopPropagation();});",
      "    at.addEventListener('keydown',function(e){",
      "      if(e.key==='Delete'||e.key==='Backspace'){e.preventDefault();remove();}",
      "    });",
      "    function drag(handle,move){",
      "      handle.addEventListener('pointerdown',function(e){",
      "        if(e.target===out)return;",
      "        e.preventDefault();",
      "        e.stopPropagation();",
      "        handle.setPointerCapture(e.pointerId);",
      "        var r=page.getBoundingClientRect();",
      "        var start={x:e.clientX,y:e.clientY,m:{x:m.x,y:m.y,w:m.w}};",
      "        function step(ev){",
      "          move((ev.clientX-start.x)/r.width,(ev.clientY-start.y)/r.height,start.m);",
      "          draw();",
      "        }",
      "        function stop(){",
      "          handle.removeEventListener('pointermove',step);",
      "          handle.removeEventListener('pointerup',stop);",
      "          handle.removeEventListener('pointercancel',stop);",
      "        }",
      "        handle.addEventListener('pointermove',step);",
      "        handle.addEventListener('pointerup',stop);",
      "        handle.addEventListener('pointercancel',stop);",
      "      });",
      "    }",
      "    drag(at,function(dx,dy,s){",
      "      m.x=Math.min(1-m.w,Math.max(0,s.x+dx));",
      "      m.y=Math.min(1,Math.max(0,s.y+dy));",
      "    });",
      "    drag(grip,function(dx,dy,s){",
      "      m.w=Math.min(1-m.x,Math.max(0.05,s.w+dx));",
      "    });",
      "    draw();",
      "    page.append(at);",
      "    marks.push(m);",
      "    sync();",
      "    at.focus();",
      "  }",
      "  document.querySelectorAll('[data-seam=page]').forEach(function(page){",
      "    page.addEventListener('click',function(e){",
      "      var r=page.getBoundingClientRect();",
      "      add(page,(e.clientX-r.left)/r.width,(e.clientY-r.top)/r.height);",
      "    });",
      "    page.addEventListener('keydown',function(e){",
      "      if(e.key==='Enter'&&e.target===page){e.preventDefault();add(page,0.5,0.5);}",
      "    });",
      "  });",
      "  if(finish)finish.addEventListener('click',function(){",
      "    finish.disabled=true;",
      "    say('Signing…');",
      "    postJson(o.post,{placements:marks.map(function(m){return {page:Number(m.page.dataset.value),x:m.x,y:m.y,w:m.w};})}).then(function(a){location.assign(a.next);}).catch(function(e){sync();say(e.message);});",
      "  });",
      "  sync();",
      "}",
      "document.querySelectorAll('[data-seam=place]').forEach(place);"
    ]
  )
end

@doc """
rows: the closed table of browser code: each name with its text.

    first(first(rows)) #=> :install
"""
def rows()
  [
    [:install, install_seam],
    [:ink, ink_seam],
    [:upload, upload_seam],
    [:place, place_seam]
  ]
end

@doc """
seam_names: The closed table of browser code, by name.

    seam_names #=> [:install, :ink, :upload, :place]
"""
def seam_names()
  map(first, rows)
end

@doc """
seam: The browser code of one row of the table, refusing a name it does not hold.

    contains?(seam(:install), "serviceWorker") #=> true
"""
def seam(name)
  found = find_first((r) -> first(r) == name, rows)
  if found.nil?
    raise(:bad_option, "seam #{to_s(name)} is not in the table")
  end
  found[1]
end

@doc """
loader: The page's one script: the install row and the rows asked for, in table order.

    contains?(loader([:install]), "'use strict'") #=> true
"""
def loader(names)
  each_known = map(seam, names)
  join(append(["'use strict';"], each_known), line_break)
end

@doc """
background_of: a theme's background as hex.

    background_of(gamen::theme({background: "#2e3440"}, :dark)) #=> "#2e3440"
"""
def background_of(theme)
  hex(theme[:tokens][:background])
end

@doc """
manifest: A web app manifest as JSON text, its colours from the theme.

    contains?(manifest({name: "x", icons: []}, gamen::theme({background: "#2e3440"}, :dark)), "standalone") #=> true
"""
def manifest(spec, theme)
  checked(spec, %i[name short_name start icons])
  json_stringify(
    {
      "name" => spec[:name],
      "short_name" => spec[:short_name] or spec[:name],
      "start_url" => spec[:start] or "/",
      "scope" => "/",
      "display" => "standalone",
      "background_color" => background_of(theme),
      "theme_color" => background_of(theme),
      "icons" => map(
        fn(i)
          {
            "src" => i[:src],
            "sizes" => "#{to_s(i[:size])}x#{to_s(i[:size])}",
            "type" => "image/png",
            "purpose" => "any"
          }
        end,
        spec[:icons]
      )
    }
  )
end

@doc """
worker: The service worker's text. Pages come from the network and fall back to the offline page; the shell is cached by version; anything else, and every write, never touches the cache, so a document is not left behind in a browser.

    contains?(worker({version: "v", shell: [], offline: "/o"}), "shell-v") #=> true
"""
def worker(spec)
  checked(spec, %i[version shell offline])
  version = spec[:version]
  shell = json_stringify(spec[:shell])
  offline = json_stringify(spec[:offline])
  cache = json_stringify("shell-#{version}")
  unlines(
    [
      "'use strict';",
      "const CACHE=#{cache};",
      "const SHELL=#{shell};",
      "const OFFLINE=#{offline};",
      "self.addEventListener('install',function(e){",
      "  e.waitUntil(caches.open(CACHE).then(function(c){return c.addAll(SHELL);}).then(function(){return self.skipWaiting();}));",
      "});",
      "self.addEventListener('activate',function(e){",
      "  e.waitUntil(caches.keys().then(function(names){",
      "    return Promise.all(names.filter(function(n){return n!==CACHE;}).map(function(n){return caches.delete(n);}));",
      "  }).then(function(){return self.clients.claim();}));",
      "});",
      "self.addEventListener('fetch',function(e){",
      "  var r=e.request;",
      "  if(r.method!=='GET')return;",
      "  var u=new URL(r.url);",
      "  if(u.origin!==location.origin)return;",
      "  if(r.mode==='navigate'){",
      "    e.respondWith(fetch(r).catch(function(){return caches.match(OFFLINE);}));",
      "    return;",
      "  }",
      "  if(SHELL.indexOf(u.pathname)>=0){",
      "    e.respondWith(caches.match(u.pathname).then(function(hit){return hit||fetch(r);}));",
      "  }",
      "});"
    ]
  )
end

@doc """
page_policy: The page security policy an installable page needs on top of a base.

    contains?(page_policy("default-src 'none'"), "worker-src 'self'") #=> true
"""
def page_policy(base)
  "#{base}; script-src 'self'; connect-src 'self'; manifest-src 'self'; worker-src 'self'"
end

@doc """
spec_fixture: a worker declaration for the tests.

    spec_fixture[:version] #=> "v1"
"""
def spec_fixture()
  {version: "v1", shell: %w[/app.js /offline], offline: "/offline"}
end

test "the table is closed: every row has code, an unknown one is refused alone"
  assert every?((n) -> length(seam(n)) > 0, seam_names)
  r = seam(:nope) rescue :refused
  assert r == :refused
  assert contains?(loader([:ink]), "getCoalescedEvents")
  assert contains?(loader([]), "getCoalescedEvents") == false
end

test "no row reaches for code from elsewhere or evaluates text"
  all = loader(seam_names)
  assert every?(
    (bad) -> contains?(all, bad) == false,
    [
      "eval(",
      "new Function",
      "innerHTML",
      "document.write",
      "importScripts",
      "http://",
      "https://"
    ]
  )
end

test "the worker never caches a write or an unlisted path, and names its version"
  w = worker(spec_fixture)
  assert contains?(w, "shell-v1")
  assert contains?(w, "if(r.method!=='GET')return")
  assert contains?(w, "cache.put") == false
  assert contains?(w, "[\"/app.js\",\"/offline\"]")
end

test "the manifest takes its colours from the theme, not from a literal"
  t = gamen::theme({background: "#2e3440"}, :dark)
  m = json_parse(manifest({name: "x", icons: [{src: "/i.png", size: 192}]}, t))
  assert json_get(m, :theme_color) == background_of(t)
  assert json_get(m, :display) == "standalone"
  assert json_get(m, :short_name) == "x"
  assert raised(() -> manifest({name: "x", icons: [], stray: 1}, t)) != nil
end
