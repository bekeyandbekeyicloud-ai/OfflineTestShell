import SwiftUI

struct SheetsView: View {
    @EnvironmentObject private var session: AppSession
    @ObservedObject var model: SheetEditorModel
    @State private var showFormats = false
    @State private var zoom: CGFloat = 1
    @GestureState private var pinchScale: CGFloat = 1
    private let rowWidth: CGFloat = 44
    private var effectiveZoom: CGFloat { min(2,max(0.5,zoom * pinchScale)) }

    var body: some View {
        VStack(spacing:0) {
            toolbar
            if model.isLoading { loading }
            else if let error=model.errorMessage, model.sheets.isEmpty { errorView(error) }
            else {
                sheetPicker
                editBar
                if showFormats { formatBar }
                grid
                statusBar
            }
        }
        .background(Color(white:0.08).ignoresSafeArea())
        .task { if model.sheets.isEmpty { await model.loadMetadata() } }
    }

    private var toolbar: some View {
        HStack {
            Image(systemName:"tablecells"); Text(model.documentTitle.isEmpty ? "表格":model.documentTitle).font(.headline).lineLimit(1)
            Spacer()
            Button { showFormats.toggle() } label:{ Image(systemName:"paintbrush.fill") }.disabled(model.selectedStart == nil)
            Button { zoom = 1 } label:{ Text("\(Int(effectiveZoom * 100))%").font(.caption.monospacedDigit()) }
            Button { Task{await model.reload()} } label:{ Image(systemName:"arrow.clockwise") }.disabled(model.isLoading)
            Button { session.lock() } label:{ Image(systemName:"lock.fill") }
        }.padding(.horizontal,14).frame(height:46).foregroundStyle(.white).background(.black)
    }

    private var loading: some View {
        VStack { Spacer(); ProgressView(value:model.loadingProgress){Text("正在读取表格与格式…")}.progressViewStyle(.linear).padding(32); Spacer() }
    }

    private var sheetPicker: some View {
        HStack {
            Picker("工作表",selection:Binding(get:{model.selectedSheetIndex},set:{i in Task{await model.selectSheet(at:i)}})) {
                ForEach(Array(model.sheets.enumerated()),id:\.offset){i,s in Text(s.name).tag(i)}
            }.pickerStyle(.menu).tint(.green)
            Spacer()
            Button { model.rangeMode.toggle(); model.clearSelection() } label:{
                Label(model.rangeMode ? "点选结束格":"选择范围",systemImage:"rectangle.dashed")
            }.buttonStyle(.bordered).tint(model.rangeMode ? .green:.gray).controlSize(.small)
        }.padding(.horizontal,10).frame(height:42).background(Color(white:0.13))
    }

    private var editBar: some View {
        HStack(spacing:8) {
            Text(model.selectionLabel).font(.caption.monospaced()).frame(width:78)
            TextField("选择单元格后编辑",text:$model.editorText)
                .textFieldStyle(.roundedBorder).submitLabel(.done)
                .onSubmit { Task{await model.saveEditorText()} }
            Button("保存") { Task{await model.saveEditorText()} }.disabled(model.selectedStart == nil)
        }.padding(.horizontal,8).frame(height:44).background(Color(white:0.96))
    }

    private var formatBar: some View {
        ScrollView(.horizontal,showsIndicators:false) {
            HStack(spacing:8) {
                Button { Task{await model.toggleBold()} } label:{ Image(systemName:"bold") }
                Menu { ForEach([8,10,12,14,16,18,20,24,28],id:\.self){size in Button("\(size)"){Task{await model.applyFontSize(Double(size))}}} } label:{ Image(systemName:"textformat.size") }
                Menu("填充色") { colorButtons(background:true) }
                Menu("文字色") { colorButtons(background:false) }
                Button { Task{await model.applyAlignment("left")} } label:{Image(systemName:"text.alignleft")}
                Button { Task{await model.applyAlignment("center")} } label:{Image(systemName:"text.aligncenter")}
                Button { Task{await model.applyAlignment("right")} } label:{Image(systemName:"text.alignright")}
                Button("合并") { Task{await model.merge()} }
                Button("取消合并") { Task{await model.unmerge()} }
                Menu("行高") {
                    Button("增加"){Task{await model.resizeRow(delta:8)}}; Button("减小"){Task{await model.resizeRow(delta:-8)}}
                }
                Menu("列宽") {
                    Button("增加"){Task{await model.resizeColumn(delta:20)}}; Button("减小"){Task{await model.resizeColumn(delta:-20)}}
                }
            }.buttonStyle(.bordered).controlSize(.small).padding(.horizontal,8)
        }.frame(height:42).background(Color(white:0.9))
    }

    @ViewBuilder private func colorButtons(background:Bool) -> some View {
        let colors=[("白色","#ffffff"),("灰色","#d9d9d9"),("红色","#f4cccc"),("橙色","#fce5cd"),("黄色","#fff2cc"),("绿色","#d9ead3"),("蓝色","#cfe2f3"),("紫色","#d9d2e9"),("黑色","#000000")]
        ForEach(colors,id:\.1){name,hex in Button(name){Task{if background{await model.applyBackground(hex)}else{await model.applyForeground(hex)}}}}
    }

    private var grid: some View {
        ScrollView([.horizontal,.vertical]) {
            LazyVStack(spacing:0,pinnedViews:[.sectionHeaders]) {
                Section {
                    ForEach(model.rowIndices,id:\.self){row in
                        HStack(spacing:0) {
                            header(String(row),width:rowWidth,height:model.rowHeight(row))
                            ForEach(model.columnIndices,id:\.self){column in cell(row:row,column:column) }
                        }
                    }
                } header:{
                    HStack(spacing:0) { header("",width:rowWidth); ForEach(model.columnIndices,id:\.self){header(model.columnName($0),width:model.columnWidth($0))} }.zIndex(3)
                }
            }
        }
        .simultaneousGesture(MagnificationGesture()
            .updating($pinchScale) { value,state,_ in state=value }
            .onEnded { value in zoom=min(2,max(0.5,zoom*value)) })
        .scrollDismissesKeyboard(.interactively).background(.white)
    }

    private func cell(row:Int,column:Int)->some View {
        let item=model.cell(row:row,column:column), selected=model.isSelected(row:row,column:column)
        let width=model.columnWidth(column)*effectiveZoom, height=model.rowHeight(row)*effectiveZoom
        return Button { model.tap(row:row,column:column) } label:{
            Text(item.value).font(.system(size:max(7,min(32,item.fontSize*effectiveZoom)),weight:item.bold ? .bold:.regular))
                .foregroundStyle(Color(hex:item.foreground)).lineLimit(1)
                .frame(maxWidth:.infinity,alignment:alignment(item.alignment)).padding(.horizontal,5)
                .frame(width:width,height:height).background(Color(hex:item.background))
                .overlay(Rectangle().stroke(selected ? Color.green:Color(white:0.8),lineWidth:selected ? 2:0.5))
        }.buttonStyle(.plain)
    }

    private func alignment(_ value:String)->Alignment { value == "center" ? .center : (value == "right" ? .trailing:.leading) }
    private func header(_ text:String,width:CGFloat,height:CGFloat=32)->some View { Text(text).font(.caption.bold()).foregroundStyle(.secondary).frame(width:width*effectiveZoom,height:height*effectiveZoom).background(Color(white:0.92)).overlay(Rectangle().stroke(Color(white:0.75),lineWidth:0.5)) }

    private var statusBar:some View {
        HStack { if model.isSaving{ProgressView().controlSize(.small);Text("正在同步…")}else if let e=model.errorMessage{Image(systemName:"exclamationmark.circle");Text(e)}else{Image(systemName:"checkmark.circle");Text("内容和格式会同步保存")};Spacer() }
            .font(.caption).foregroundStyle(model.errorMessage == nil ? Color.secondary:.red).padding(.horizontal,10).frame(height:32).background(Color(white:0.95))
    }
    private func errorView(_ error:String)->some View { VStack(spacing:12){Spacer();Image(systemName:"exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange);Text(error).font(.caption);Button("重试"){Task{await model.loadMetadata()}};Spacer()} }
}

private extension Color {
    init(hex:String) { let cleaned=hex.trimmingCharacters(in:CharacterSet.alphanumerics.inverted);var v:UInt64=0;Scanner(string:cleaned).scanHexInt64(&v);if cleaned.count==6{self.init(.sRGB,red:Double(v>>16)/255,green:Double((v>>8)&255)/255,blue:Double(v&255)/255,opacity:1)}else{self = .white} }
}

