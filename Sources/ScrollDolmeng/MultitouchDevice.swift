import CoreFoundation
@preconcurrency import MultitouchSupport

@_silgen_name("MTDeviceCreateList")
private func MTDeviceCreateListShim() -> Unmanaged<CFMutableArray>?

extension MTDevice {
    static func createList() -> [MTDevice] {
        MTDeviceCreateListShim()?.takeRetainedValue() as? [MTDevice] ?? []
    }

    func registerAndStart(_ callback: MTFrameCallbackFunction) {
        _ = register(contactFrameCallback: callback)
        start(runMode: 0)
    }

    func unregisterAndStop(_ callback: MTFrameCallbackFunction) {
        _ = unregister(contactFrameCallback: callback)
        stop()
    }

    var surfaceSize: CGSize? {
        var width: Int32 = 0
        var height: Int32 = 0
        guard MTDeviceGetSensorSurfaceDimensions(self, &width, &height) == 0 else {
            return nil
        }
        return CGSize(width: CGFloat(width), height: CGFloat(height))
    }
}
