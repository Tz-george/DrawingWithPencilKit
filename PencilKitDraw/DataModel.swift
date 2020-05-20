/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The app's data model for storing drawings, thumbnails, and signatures.
*/

/// Underlying the app's data model is a cross-platform `PKDrawing` object. `PKDrawing` adheres to `Codable`
/// in Swift, or you can fetch its data representation as a `Data` object through its `dataRepresentation()`
/// method. `PKDrawing` is the only PencilKit type supported on non-iOS platforms.

/// From `PKDrawing`'s `image(from:scale:)` method, you can get an image to save, or you can transform a
/// `PKDrawing` and append it to another drawing.

/// If you already have some saved `PKDrawing`s, you can make them available in this sample app by adding them
/// to the project's "Assets" catalog, and adding their asset names to the `defaultDrawingNames` array below.

import UIKit
import PencilKit
import os

/// `DataModel` contains the drawings that make up the data model, including multiple image drawings and a signature drawing.
struct DataModel: Codable {
    
    /// Names of the drawing assets to be used to initialize the data model the first time.
    static let defaultDrawingNames: [String] = ["Notes"]
    
    /// The width used for drawing canvases.
    static let canvasWidth: CGFloat = 768   // 画布的宽
    
    /// The drawings that make up the current data model.
    var drawings: [PKDrawing] = []  // 绘画数据列表
    var signature = PKDrawing() // canvas视图捕捉到的绘图信息
}

/// `DataModelControllerObserver` is the behavior of an observer of data model changes.
protocol DataModelControllerObserver {
    /// Invoked when the data model changes.
    func dataModelChanged()
}

/// `DataModelController` coordinates changes to the data  model.
class DataModelController {
    
    /// The underlying data model.
    var dataModel = DataModel()     // 低层数据
    
    /// Thumbnail images representing the drawings in the data model.
    var thumbnails = [UIImage]()        // 画布绘画内容集合
    var thumbnailTraitCollection = UITraitCollection() {    // 界面管理器，并且设置属性观察者
        didSet {
            // If the user interface style changed, regenerate all thumbnails.
            // 设置当界面样式变化时，重绘画布的绘画内容
            if oldValue.userInterfaceStyle != thumbnailTraitCollection.userInterfaceStyle {
                generateAllThumbnails()
            }
        }
    }
    
    /// Dispatch queues for the background operations done by this controller.
    private let thumbnailQueue = DispatchQueue(label: "ThumbnailQueue", qos: .background)   // 绘画调度队列，用于异步绘图
    private let serializationQueue = DispatchQueue(label: "SerializationQueue", qos: .background) // 调度队列，序列
    
    /// Observers add themselves to this array to start being informed of data model changes.
    var observers = [DataModelControllerObserver]() // 数据观察者
    
    /// The size to use for thumbnail images.
    static let thumbnailSize = CGSize(width: 192, height: 256)
    
    /// Computed property providing access to the drawings in the data model.
    var drawings: [PKDrawing] { // 计算属性，将绘画内容保存在datamodel的绘画列表中
        get { dataModel.drawings }
        set { dataModel.drawings = newValue }
    }
    /// Computed property providing access to the signature in the data model.
    var signature: PKDrawing {  // 计算属性，将当前绘画内容保存到datamodel的当前图像属性中
        get { dataModel.signature }
        set { dataModel.signature = newValue }
    }
    
    /// Initialize a new data model.
    init() {
        loadDataModel()
    }
    
    /// Update a drawing at `index` and generate a new thumbnail.
    func updateDrawing(_ drawing: PKDrawing, at index: Int) {   //
        dataModel.drawings[index] = drawing
        generateThumbnail(index)
        saveDataModel()
    }
    
    /// Helper method to cause regeneration of all thumbnails.
    private func generateAllThumbnails() {  // 重绘画布的绘画内容
        for index in drawings.indices {
            generateThumbnail(index)        // 重绘函数
        }
    }
    
    /// Helper method to cause regeneration of a specific thumbnail, using the current user interface style
    /// of the thumbnail view controller.
    private func generateThumbnail(_ index: Int) {  // 实际的重绘函数
        let drawing = drawings[index]   // 首先拿到绘图内容
        let aspectRatio = DataModelController.thumbnailSize.width / DataModelController.thumbnailSize.height    // 计算画布的长宽比
        let thumbnailRect = CGRect(x: 0, y: 0, width: DataModel.canvasWidth, height: DataModel.canvasWidth / aspectRatio)   // 绘画的矩形框
        let thumbnailScale = UIScreen.main.scale * DataModelController.thumbnailSize.width / DataModel.canvasWidth  // 比例系数，比例系数越大，图像越精细。比例系数 = 屏幕的比例系数 *
        let traitCollection = thumbnailTraitCollection
        
        thumbnailQueue.async {  // 向绘画队列中入队一个绘画动作，之后绘画队列会自动执行，尾随闭包的写法：当函数的最后一个参数是函数类型时，可以将闭包函数提到函数调用的括号外，如果函数只有一个参数，且为函数类型时，可以省略括号
            traitCollection.performAsCurrent {  // 使用当前的特征集合内的特征执行自定义代码，参数是回调函数
                let image = drawing.image(from: thumbnailRect, scale: thumbnailScale)   // 获取图像
                DispatchQueue.main.async {      // 主线程调度队列
                    self.updateThumbnail(image, at: index)  // 调用更新画布内容函数
                }
            }
        }
    }
    
    /// Helper method to replace a thumbnail at a given index.
    private func updateThumbnail(_ image: UIImage, at index: Int) { // 替换掉图片
        thumbnails[index] = image
        didChange()
    }
    
    /// Helper method to notify observer that the data model changed.
    private func didChange() {  // 通知所有的观察者数据已经变动
        for observer in self.observers {
            observer.dataModelChanged() // 调用观察者的数据变动函数，所有观察者都必须实现
        }
    }
    
    /// The URL of the file in which the current data model is saved.
    private var saveURL: URL {  // 计算属性：获取保存用的URL
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)  // 创建一个可用于存放数据的地址
        let documentsDirectory = paths.first!
        return documentsDirectory.appendingPathComponent("PencilKitDraw.data")
    }
    
    /// Save the data model to persistent storage.
    func saveDataModel() {  // 保存数据
        let savingDataModel = dataModel
        let url = saveURL
        serializationQueue.async {  // 操作 队列
            do {
                let encoder = PropertyListEncoder() // 创建一个用于将数据转换成可存储的数据类型的对象
                let data = try encoder.encode(savingDataModel)  // 编码
                try data.write(to: url)     // 存储
            } catch {
                os_log("Could not save data model: %s", type: .error, error.localizedDescription)
            }
        }
    }
    
    /// Load the data model from persistent storage
    private func loadDataModel() {  // 读取数据
        let url = saveURL               //
        serializationQueue.async {
            // Load the data model, or the initial test data.
            let dataModel: DataModel
            
            if FileManager.default.fileExists(atPath: url.path) {
                do {
                    let decoder = PropertyListDecoder() // 解码器
                    let data = try Data(contentsOf: url)    //  读取数据
                    dataModel = try decoder.decode(DataModel.self, from: data)  // 解码
                } catch {
                    os_log("Could not load data model: %s", type: .error, error.localizedDescription)
                    dataModel = self.loadDefaultDrawings()  // 报错的话还是得有一个初始界面
                }
            } else {
                dataModel = self.loadDefaultDrawings()
            }
            
            DispatchQueue.main.async {  // 将操作设置进主线程
                self.setLoadedDataModel(dataModel)
            }
        }
    }
    
    /// Construct initial an data model when no data model already exists.
    private func loadDefaultDrawings() -> DataModel {   // 为使程序正常运行，需要有一个默认的dataModel
        var testDataModel = DataModel() // 创建DataModel结构体
        for sampleDataName in DataModel.defaultDrawingNames {   // 默认数据
            guard let data = NSDataAsset(name: sampleDataName)?.data else { continue }  // 读取 Assets.xcassets/Notes.dataset/Contents.json 中的数据
            if let drawing = try? PKDrawing(data: data) {   // 生成一个笔画
                testDataModel.drawings.append(drawing)      //
            }
        }
        return testDataModel
    }
    
    /// Helper method to set the current data model to a data model created on a background queue.
    private func setLoadedDataModel(_ dataModel: DataModel) {   // 数据加载
        self.dataModel = dataModel  // 设置dataModel
        thumbnails = Array(repeating: UIImage(), count: dataModel.drawings.count)   // 设置thumbnails
        generateAllThumbnails() // 画
    }
    
    /// Create a new drawing in the data model.
    func newDrawing() {             // 辅助函数，
        let newDrawing = PKDrawing()
        dataModel.drawings.append(newDrawing)
        thumbnails.append(UIImage())
        updateDrawing(newDrawing, at: dataModel.drawings.count - 1)
    }
}
