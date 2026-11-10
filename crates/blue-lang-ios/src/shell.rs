use std::cell::{Cell, OnceCell, RefCell};
use std::io::Write;
use std::ptr::NonNull;
use std::time::{Duration, Instant};

use objc2::rc::{Allocated, Retained};
use objc2::runtime::{AnyClass, ProtocolObject};
use objc2::{define_class, msg_send, sel, ClassType, DefinedClass, MainThreadOnly};
use objc2_core_foundation::{CGRect, CGSize};
use objc2_foundation::{
    MainThreadMarker, NSDefaultRunLoopMode, NSObject, NSObjectProtocol, NSRunLoop, NSSet, NSString,
};
use objc2_metal::{
    MTLClearColor, MTLCommandBuffer, MTLCommandEncoder, MTLCommandQueue,
    MTLCreateSystemDefaultDevice, MTLDevice, MTLDrawable, MTLLibrary, MTLLoadAction,
    MTLPixelFormat, MTLPrimitiveType, MTLRenderCommandEncoder, MTLRenderPassDescriptor,
    MTLRenderPipelineDescriptor, MTLRenderPipelineState, MTLResourceOptions, MTLStoreAction,
};
use objc2_quartz_core::{CADisplayLink, CAFrameRateRange, CAMetalDrawable, CAMetalLayer};
use objc2_ui_kit::{
    UIApplication, UIApplicationDelegate, UIEvent, UIScene, UISceneConnectionOptions,
    UISceneDelegate, UISceneSession, UIScreen, UITouch, UIView, UIViewController, UIWindow,
    UIWindowScene, UIWindowSceneDelegate,
};

use crate::draw::{self, Frame, FLOATS_PER_VERTEX};
use crate::program::{App, Event, Input, Phase};

const MSL: &str = "#include <metal_stdlib>
using namespace metal;
struct V { float2 p; float2 pad; float4 c; };
struct O { float4 pos [[position]]; float4 c; };
vertex O blue_vertex(uint vid [[vertex_id]], const device V* vs [[buffer(0)]]) {
  O o;
  o.pos = float4(vs[vid].p, 0.0, 1.0);
  o.c = vs[vid].c;
  return o;
}
fragment float4 blue_fragment(O i [[stage_in]]) { return i.c; }
";

const REPORT_EVERY: usize = 120;
const CONSOLE_FILE: &str = "Documents/blue-ios-console.txt";

thread_local! {
    static LOADED: RefCell<Option<App>> = const { RefCell::new(None) };
}

fn console_path() -> Option<std::path::PathBuf> {
    std::env::var_os("HOME").map(|home| std::path::Path::new(&home).join(CONSOLE_FILE))
}

fn say(line: &str) {
    let mut out = std::io::stdout();
    let _ = writeln!(out, "blue-ios: {line}");
    let _ = out.flush();
    if let Some(path) = console_path() {
        if let Ok(mut f) = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(path)
        {
            let _ = writeln!(f, "blue-ios: {line}");
        }
    }
}

struct Renderer {
    device: Retained<ProtocolObject<dyn MTLDevice>>,
    queue: Retained<ProtocolObject<dyn objc2_metal::MTLCommandQueue>>,
    pipeline: Retained<ProtocolObject<dyn MTLRenderPipelineState>>,
}

impl Renderer {
    fn new() -> Result<Self, String> {
        let device = MTLCreateSystemDefaultDevice().ok_or("no Metal device")?;
        let queue = device.newCommandQueue().ok_or("no command queue")?;
        let library = device
            .newLibraryWithSource_options_error(&NSString::from_str(MSL), None)
            .map_err(|e| e.localizedDescription().to_string())?;
        let vertex = library
            .newFunctionWithName(&NSString::from_str("blue_vertex"))
            .ok_or("no blue_vertex")?;
        let fragment = library
            .newFunctionWithName(&NSString::from_str("blue_fragment"))
            .ok_or("no blue_fragment")?;
        let desc = MTLRenderPipelineDescriptor::new();
        desc.setVertexFunction(Some(&vertex));
        desc.setFragmentFunction(Some(&fragment));
        let c0 = unsafe { desc.colorAttachments().objectAtIndexedSubscript(0) };
        c0.setPixelFormat(MTLPixelFormat::BGRA8Unorm);
        let pipeline = device
            .newRenderPipelineStateWithDescriptor_error(&desc)
            .map_err(|e| e.localizedDescription().to_string())?;
        Ok(Self {
            device,
            queue,
            pipeline,
        })
    }

    fn configure(&self, layer: &CAMetalLayer) {
        layer.setDevice(Some(&self.device));
        layer.setPixelFormat(MTLPixelFormat::BGRA8Unorm);
    }

    fn draw(&self, layer: &CAMetalLayer, frame: &Frame, width: f32, height: f32) {
        let Some(drawable) = layer.nextDrawable() else {
            return;
        };
        let Some(cmd) = self.queue.commandBuffer() else {
            return;
        };
        let clear = frame.clear_colour();
        let pass = MTLRenderPassDescriptor::new();
        let a0 = unsafe { pass.colorAttachments().objectAtIndexedSubscript(0) };
        a0.setTexture(Some(&drawable.texture()));
        a0.setLoadAction(MTLLoadAction::Clear);
        a0.setStoreAction(MTLStoreAction::Store);
        a0.setClearColor(MTLClearColor {
            red: f64::from(clear.r),
            green: f64::from(clear.g),
            blue: f64::from(clear.b),
            alpha: f64::from(clear.a),
        });
        let Some(enc) = cmd.renderCommandEncoderWithDescriptor(&pass) else {
            return;
        };
        let floats = draw::vertices(frame, width, height);
        if !floats.is_empty() {
            let bytes = std::mem::size_of_val(floats.as_slice());
            let ptr = NonNull::from(floats.as_slice()).cast::<core::ffi::c_void>();
            let buffer = unsafe {
                self.device.newBufferWithBytes_length_options(
                    ptr,
                    bytes,
                    MTLResourceOptions::StorageModeShared,
                )
            };
            if let Some(buffer) = buffer {
                enc.setRenderPipelineState(&self.pipeline);
                unsafe {
                    enc.setVertexBuffer_offset_atIndex(Some(&buffer), 0, 0);
                    enc.drawPrimitives_vertexStart_vertexCount(
                        MTLPrimitiveType::Triangle,
                        0,
                        floats.len() / FLOATS_PER_VERTEX,
                    );
                }
            }
        }
        enc.endEncoding();
        let presentable: &ProtocolObject<dyn MTLDrawable> = ProtocolObject::from_ref(&*drawable);
        cmd.presentDrawable(presentable);
        cmd.commit();
    }
}

#[derive(Default)]
struct Stats {
    blue: Vec<Duration>,
    whole: Vec<Duration>,
    frames: usize,
}

impl Stats {
    fn record(&mut self, blue: Duration, whole: Duration) {
        self.frames += 1;
        self.blue.push(blue);
        self.whole.push(whole);
        if self.blue.len() == REPORT_EVERY {
            let line = format!(
                "frames {} blue frame p50 {:.3} ms max {:.3} ms; whole step p50 {:.3} ms max {:.3} ms",
                self.frames,
                ms(median(&mut self.blue)),
                ms(self.blue.iter().copied().max().unwrap_or_default()),
                ms(median(&mut self.whole)),
                ms(self.whole.iter().copied().max().unwrap_or_default()),
            );
            say(&line);
            self.blue.clear();
            self.whole.clear();
        }
    }
}

fn median(xs: &mut [Duration]) -> Duration {
    xs.sort_unstable();
    xs.get(xs.len() / 2).copied().unwrap_or_default()
}

fn ms(d: Duration) -> f64 {
    d.as_secs_f64() * 1000.0
}

#[derive(Default)]
pub struct ViewIvars {
    app: RefCell<Option<App>>,
    renderer: OnceCell<Renderer>,
    link: OnceCell<Retained<CADisplayLink>>,
    pending: RefCell<Vec<Event>>,
    stats: RefCell<Stats>,
    faulted: Cell<bool>,
    first: Cell<bool>,
}

define_class!(
    #[unsafe(super(UIView))]
    #[thread_kind = MainThreadOnly]
    #[name = "BlueView"]
    #[ivars = ViewIvars]
    pub struct BlueView;

    unsafe impl NSObjectProtocol for BlueView {}

    impl BlueView {
        #[unsafe(method(layerClass))]
        fn layer_class() -> &'static AnyClass {
            CAMetalLayer::class()
        }

        #[unsafe(method(step:))]
        fn step(&self, link: &CADisplayLink) {
            self.tick(link.timestamp());
        }

        #[unsafe(method(touchesBegan:withEvent:))]
        fn touches_began(&self, touches: &NSSet<UITouch>, _event: Option<&UIEvent>) {
            self.collect(touches, Phase::Began);
        }

        #[unsafe(method(touchesMoved:withEvent:))]
        fn touches_moved(&self, touches: &NSSet<UITouch>, _event: Option<&UIEvent>) {
            self.collect(touches, Phase::Moved);
        }

        #[unsafe(method(touchesEnded:withEvent:))]
        fn touches_ended(&self, touches: &NSSet<UITouch>, _event: Option<&UIEvent>) {
            self.collect(touches, Phase::Ended);
        }

        #[unsafe(method(touchesCancelled:withEvent:))]
        fn touches_cancelled(&self, touches: &NSSet<UITouch>, _event: Option<&UIEvent>) {
            self.collect(touches, Phase::Cancelled);
        }
    }
);

impl BlueView {
    fn new(mtm: MainThreadMarker, screen: &UIScreen, frame: CGRect, app: App) -> Retained<Self> {
        let ivars = ViewIvars::default();
        *ivars.app.borrow_mut() = Some(app);
        let this = mtm.alloc::<Self>().set_ivars(ivars);
        let this: Retained<Self> = unsafe { msg_send![super(this), initWithFrame: frame] };
        this.setMultipleTouchEnabled(true);
        let layer = this.metal_layer();
        let scale = screen.scale();
        layer.setContentsScale(scale);
        let size = this.bounds().size;
        layer.setDrawableSize(CGSize {
            width: size.width * scale,
            height: size.height * scale,
        });
        match Renderer::new() {
            Ok(r) => {
                r.configure(&layer);
                let _ = this.ivars().renderer.set(r);
            }
            Err(e) => say(&format!("metal: {e}")),
        }
        this.start_link(screen);
        this
    }

    fn metal_layer(&self) -> Retained<CAMetalLayer> {
        let layer = self.layer();
        let ptr = Retained::into_raw(layer).cast::<CAMetalLayer>();
        unsafe { Retained::from_raw(ptr) }.expect("layerClass is CAMetalLayer")
    }

    fn start_link(&self, screen: &UIScreen) {
        let link = unsafe { CADisplayLink::displayLinkWithTarget_selector(self, sel!(step:)) };
        let max = screen.maximumFramesPerSecond() as f32;
        link.setPreferredFrameRateRange(CAFrameRateRange {
            minimum: 60.0_f32.min(max),
            maximum: max,
            preferred: max,
        });
        unsafe { link.addToRunLoop_forMode(&NSRunLoop::currentRunLoop(), NSDefaultRunLoopMode) };
        let _ = self.ivars().link.set(link);
    }

    fn collect(&self, touches: &NSSet<UITouch>, phase: Phase) {
        let mut pending = self.ivars().pending.borrow_mut();
        for touch in touches.allObjects().iter() {
            let p = touch.locationInView(Some(self));
            pending.push(Event::Touch {
                phase,
                x: p.x,
                y: p.y,
            });
        }
    }

    fn tick(&self, t: f64) {
        let ivars = self.ivars();
        if ivars.faulted.get() {
            return;
        }
        let started = Instant::now();
        let size = self.bounds().size;
        let mut slot = ivars.app.borrow_mut();
        let Some(app) = slot.as_mut() else {
            return;
        };
        for event in ivars.pending.borrow_mut().drain(..) {
            if let Err(e) = app.event(event) {
                say(&format!("event: {e}"));
            }
        }
        let blue_started = Instant::now();
        let frame = match app.frame(Input {
            t,
            width: size.width,
            height: size.height,
        }) {
            Ok(f) => f,
            Err(e) => {
                say(&format!("frame: {e}"));
                ivars.faulted.set(true);
                return;
            }
        };
        let blue = blue_started.elapsed();
        if !ivars.first.replace(true) {
            say(&format!(
                "first frame: {} draws, {} refused {:?}",
                frame.draws.len(),
                frame.refused.len(),
                frame.refused
            ));
        }
        if let Some(r) = ivars.renderer.get() {
            r.draw(
                &self.metal_layer(),
                &frame,
                size.width as f32,
                size.height as f32,
            );
        }
        ivars.stats.borrow_mut().record(blue, started.elapsed());
    }
}

define_class!(
    #[unsafe(super(NSObject))]
    #[thread_kind = MainThreadOnly]
    #[name = "BlueAppDelegate"]
    pub struct AppDelegate;

    unsafe impl NSObjectProtocol for AppDelegate {}

    unsafe impl UIApplicationDelegate for AppDelegate {
        #[unsafe(method(application:didFinishLaunchingWithOptions:))]
        fn did_finish_launching(
            &self,
            _application: &UIApplication,
            _options: *mut objc2_foundation::NSDictionary,
        ) -> bool {
            true
        }
    }
);

#[derive(Default)]
pub struct SceneIvars {
    window: OnceCell<Retained<UIWindow>>,
}

define_class!(
    #[unsafe(super(NSObject))]
    #[thread_kind = MainThreadOnly]
    #[name = "BlueSceneDelegate"]
    #[ivars = SceneIvars]
    pub struct SceneDelegate;

    unsafe impl NSObjectProtocol for SceneDelegate {}

    impl SceneDelegate {
        #[unsafe(method_id(init))]
        fn init(this: Allocated<Self>) -> Option<Retained<Self>> {
            unsafe { msg_send![super(this.set_ivars(SceneIvars::default())), init] }
        }
    }

    unsafe impl UISceneDelegate for SceneDelegate {
        #[unsafe(method(scene:willConnectToSession:options:))]
        fn scene_will_connect(
            &self,
            scene: &UIScene,
            _session: &UISceneSession,
            _options: &UISceneConnectionOptions,
        ) {
            let mtm = MainThreadMarker::from(self);
            let Some(window_scene) = scene.downcast_ref::<UIWindowScene>() else {
                return;
            };
            let Some(app) = LOADED.with(|l| l.borrow_mut().take()) else {
                say("scene connected with no loaded program");
                return;
            };
            let window = UIWindow::initWithWindowScene(UIWindow::alloc(mtm), window_scene);
            let screen = window_scene.screen();
            let bounds = screen.bounds();
            window.setFrame(bounds);
            let controller = UIViewController::new(mtm);
            let view = BlueView::new(mtm, &screen, bounds, app);
            controller.setView(Some(&view));
            window.setRootViewController(Some(&controller));
            window.makeKeyAndVisible();
            let _ = self.ivars().window.set(window);
        }
    }

    unsafe impl UIWindowSceneDelegate for SceneDelegate {}
);

pub fn run() {
    let mtm = MainThreadMarker::new().expect("main thread");
    if let Some(path) = console_path() {
        let _ = std::fs::write(path, "");
    }
    let path = std::env::current_exe()
        .ok()
        .and_then(|exe| exe.parent().map(|dir| dir.join(crate::PROGRAM_FILE)));
    let Some(path) = path else {
        say("cannot find the bundle directory");
        std::process::exit(1);
    };
    let source = match std::fs::read_to_string(&path) {
        Ok(s) => s,
        Err(e) => {
            say(&format!("cannot read {}: {e}", path.display()));
            std::process::exit(1);
        }
    };
    let app = match App::load(&source) {
        Ok(app) => app,
        Err(e) => {
            say(&format!("load: {e}"));
            std::process::exit(1);
        }
    };
    say(&format!("init() = {}", app.state()));
    LOADED.with(|l| *l.borrow_mut() = Some(app));
    let _ = SceneDelegate::class();
    let delegate = NSString::from_str(AppDelegate::class().name().to_str().unwrap_or_default());
    UIApplication::main(None, Some(&delegate), mtm);
}
