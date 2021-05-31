import SwiftUI
import Combine

final class CenteringScrollView: UIScrollView {
  var shouldCenter = true

  func centerContent() {
    assert(subviews.count == 1)
    subviews.forEach {
      $0.center = self.center
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    if self.shouldCenter {
      self.centerContent()
    }
  }
}

struct ZoomableScrollView<Content: View>: View {
  let content: Content
  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  @State private var doubleTap = PassthroughSubject<Void, Never>()

  var body: some View {
    ZoomableScrollViewImpl(content: content, doubleTap: doubleTap.eraseToAnyPublisher())
    /// The double tap gesture is a modifier on a SwiftUI wrapper view, rather than just putting a UIGestureRecognizer on the wrapped view,
    /// because SwiftUI and UIKit gesture recognizers don't work together correctly correctly for failure and other interactions.
    //      .onTapGesture(count: 2) {
    //        doubleTap.send()
    //      }
  }
}

fileprivate struct ZoomableScrollViewImpl<Content: View>: UIViewControllerRepresentable {
  let content: Content
  let doubleTap: AnyPublisher<Void, Never>

  func makeUIViewController(context: Context) -> ViewController {
    return ViewController(coordinator: context.coordinator, doubleTap: doubleTap)
  }

  func makeCoordinator() -> Coordinator {
    return Coordinator(hostingController: UIHostingController(rootView: self.content))
  }

  func updateUIViewController(_ viewController: ViewController, context: Context) {
    viewController.update(content: self.content, doubleTap: doubleTap)
  }

  // MARK: - ViewController

  final class ViewController: UIViewController, UIScrollViewDelegate {
    private var doubleTapGesture: UITapGestureRecognizer!
    private let coordinator: Coordinator
    private let scrollView = CenteringScrollView()

    private var doubleTapCancellable: Cancellable?
    private var updateConstraintsCancellable: Cancellable?

    private var hostedView: UIView { coordinator.hostingController.view! }

    private var contentSizeConstraints: [NSLayoutConstraint] = [] {
      willSet { NSLayoutConstraint.deactivate(contentSizeConstraints) }
      didSet { NSLayoutConstraint.activate(contentSizeConstraints) }
    }

    required init?(coder: NSCoder) { fatalError() }
    init(coordinator: Coordinator, doubleTap: AnyPublisher<Void, Never>) {
      self.coordinator = coordinator
      super.init(nibName: nil, bundle: nil)
       self.view = scrollView

      scrollView.delegate = self  // for viewForZooming(in:)
      scrollView.maximumZoomScale = 1.25
      scrollView.minimumZoomScale = 1
      scrollView.bouncesZoom = true
      scrollView.showsHorizontalScrollIndicator = false
      scrollView.showsVerticalScrollIndicator = false
      scrollView.clipsToBounds = false

      doubleTapGesture = UITapGestureRecognizer(
        target: self,
        action: #selector(handleDoubleTap(_:))
      )
      doubleTapGesture.numberOfTapsRequired = 2
      hostedView.addGestureRecognizer(self.doubleTapGesture)

      let hostedView = coordinator.hostingController.view!
      hostedView.translatesAutoresizingMaskIntoConstraints = false
      scrollView.addSubview(hostedView)
      NSLayoutConstraint.activate([
        hostedView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
        hostedView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
        hostedView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
        hostedView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
      ])

      updateConstraintsCancellable = scrollView
        .publisher(for: \.bounds).map(\.size)
        .removeDuplicates()
        .sink { [unowned self] size in
          view.setNeedsUpdateConstraints()
        }
      doubleTapCancellable = doubleTap.sink { [unowned self] in
        handleDoubleTap(self.doubleTapGesture)
      }
    }

    func update(content: Content, doubleTap: AnyPublisher<Void, Never>) {
      coordinator.hostingController.rootView = content
      scrollView.setNeedsUpdateConstraints()
      doubleTapCancellable = doubleTap.sink { [unowned self] in
        handleDoubleTap(self.doubleTapGesture)
      }
    }

    @objc private func handleDoubleTap(_ gesture: UIGestureRecognizer) {
      let scale = min(scrollView.zoomScale * 2, scrollView.maximumZoomScale)

      if scale != scrollView.zoomScale { // zoom in
        let point = gesture.location(in: hostedView)

        let scrollSize = scrollView.frame.size
        let size = CGSize(
          width: scrollSize.width / scrollView.maximumZoomScale,
          height: scrollSize.height / scrollView.maximumZoomScale
        )
        let origin = CGPoint(
          x: point.x - size.width / 2,
          y: point.y - size.height / 2
        )
        scrollView.shouldCenter = false
        scrollView.zoom(to:CGRect(origin: origin, size: size), animated: true)
      } else if scrollView.zoomScale > 1 { // zoom out
        scrollView.shouldCenter = true
        scrollView.zoom(
          to: zoomRectForScale(
            scale: scrollView.maximumZoomScale,
            center: gesture.location(in: scrollView)),
          animated: true
        )

      }
    }

    private func zoomRectForScale(scale: CGFloat, center: CGPoint) -> CGRect {
      var zoomRect = CGRect.zero
      zoomRect.size.height = hostedView.frame.size.height / scale
      zoomRect.size.width  = hostedView.frame.size.width  / scale
      let newCenter = scrollView.convert(center, from: hostedView)
      zoomRect.origin.x = newCenter.x - (zoomRect.size.width / 2.0)
      zoomRect.origin.y = newCenter.y - (zoomRect.size.height / 2.0)
      return zoomRect
    }

    override func updateViewConstraints() {
      super.updateViewConstraints()
      let hostedContentSize = coordinator.hostingController.sizeThatFits(in: view.bounds.size)
      contentSizeConstraints = [
        hostedView.widthAnchor.constraint(equalToConstant: hostedContentSize.width),
        hostedView.heightAnchor.constraint(equalToConstant: hostedContentSize.height),
      ]
    }

    override func viewDidAppear(_ animated: Bool) {
      scrollView.zoom(to: hostedView.bounds, animated: false)
    }

    override func viewDidLayoutSubviews() {
      super.viewDidLayoutSubviews()

      let hostedContentSize = coordinator.hostingController.sizeThatFits(in: view.bounds.size)
      scrollView.minimumZoomScale = min(
        scrollView.bounds.width / hostedContentSize.width,
        scrollView.bounds.height / hostedContentSize.height)
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
      // For some reason this is needed in both didZoom and layoutSubviews, thanks to https://medium.com/@ssamadgh/designing-apps-with-scroll-views-part-i-8a7a44a5adf7
      // Sometimes this seems to work (view animates size and position simultaneously from current position to center) and sometimes it does not (position snaps to center immediately, size change animates)
      if self.scrollView.shouldCenter {
        self.scrollView.centerContent()
      }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
      coordinator.animate { [unowned self] (context) in
        scrollView.zoom(to: self.hostedView.bounds, animated: false)
      }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
      return hostedView
    }
  }

  // MARK: - Coordinator

  final class Coordinator: NSObject, UIScrollViewDelegate {
    var hostingController: UIHostingController<Content>

    init(hostingController: UIHostingController<Content>) {
      self.hostingController = hostingController
    }
  }
}
