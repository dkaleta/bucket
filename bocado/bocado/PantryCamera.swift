import SwiftUI
import AVFoundation

#if os(iOS)
import UIKit

struct PantryCamera: UIViewControllerRepresentable {
    let finish: (Data?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(finish: finish) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let finish: (Data?) -> Void
        init(finish: @escaping (Data?) -> Void) { self.finish = finish }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { finish(nil) }

        func imagePickerController(_ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            finish((info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 0.92))
        }
    }
}
#elseif os(macOS)
import Quartz

// The system picture taker supports the Mac camera and Continuity Camera.
struct MacPantryCamera {
    static func capture() -> Data? {
        guard let picker = IKPictureTaker.pictureTaker() else { return nil }
        picker.setValue(false, forKey: IKPictureTakerAllowsFileChoosingKey)
        guard picker.runModal() == NSApplication.ModalResponse.OK.rawValue else { return nil }
        return picker.outputImage()?.tiffRepresentation
    }
}
#endif
