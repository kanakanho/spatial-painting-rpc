//
//  SelectingPeerView.swift
//  spatial-painting-rpc
//
//  Created by blueken on 2025/01/22.
//

import SwiftUI

struct SelectingPeerView: View {
    @ObservedObject private var rpcModel: RPCModel
    @State var peerIDHash: Int!
    @State private var errorMessage: String = ""

    init(rpcModel: RPCModel) {
        self.rpcModel = rpcModel
    }

    var body: some View {
        VStack {
            Text("2. 近くにいる人を選択").font(.title)

            // デバッグ用情報
            let standbyCount = rpcModel.mcPeerIDUUIDWrapper.standby.count
            let wrapperPtr = String(format: "%p", UInt(bitPattern: ObjectIdentifier(rpcModel.mcPeerIDUUIDWrapper)))

            Text("🔍 standby: \(standbyCount) | wrapper: \(wrapperPtr)")
                .font(.caption)
                .foregroundColor(.gray)

            ForEach(rpcModel.mcPeerIDUUIDWrapper.standby, id: \.id) { peerId in
                Text("\(peerId.displayName) [hash=\(peerId.hash)]")
                    .font(.caption)
            }

            Divider()
            Picker("", selection: $peerIDHash) {
                Text("選ぶ").tag(nil as Int?)
                ForEach(rpcModel.mcPeerIDUUIDWrapper.standby, id: \.hash) { peerId in
                    Text(String(peerId.displayName)).tag(peerId.hash)
                }
            }
            Spacer()
            Button(action: {
                confirmSelectClient()
            }){
                Text("選択した相手を確定")
            }
            
            Spacer()
            
            if !errorMessage.isEmpty {
                Text(errorMessage).foregroundColor(.red)
            }
            Button(action: {
                returnToInitial()
            }){
                Text("設定をやめる")
            }
        }
    }
    
    private func confirmSelectClient(){
        if peerIDHash != nil {
            // 通信相手の peerId の登録
            let initPeerRPCResult = rpcModel.coordinateTransforms.initOtherPeer(param: .init(peerId: peerIDHash))
            if !initPeerRPCResult.success {
                errorMessage = initPeerRPCResult.errorMessage
                return
            }
            
            // hash値が大きい方をホストとする
            let nextState: TransformationMatrixPreparationState = rpcModel.mcPeerIDUUIDWrapper.mine.hash > peerIDHash ? .getTransformMatrixClient : .getTransformMatrixHost
            // 次の画面に遷移する
            let setStateRPCResult = rpcModel.coordinateTransforms.setState(param: .init(state: nextState))
            if !setStateRPCResult.success {
                errorMessage = setStateRPCResult.errorMessage
            }
        }
    }
    
    private func returnToInitial() {
        _ = rpcModel.coordinateTransforms.resetPeer(param: .init())
    }
}
