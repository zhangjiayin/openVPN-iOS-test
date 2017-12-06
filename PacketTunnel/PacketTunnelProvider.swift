//
//  PacketTunnelProvider.swift
//  PacketTunnel
//
//  Created by 周荣水 on 2017/12/5.
//Copyright © 2017年 周荣水. All rights reserved.
//

import NetworkExtension
import KeychainAccess
import OpenVPNAdapter


enum PacketTunnelProviderError: Error {
    case fatalError(message: String)
}

class PacketTunnelProvider: NEPacketTunnelProvider {
//    var connection: NWTCPConnection? = nil
//    var pendingStartCompletion: ((NSError?) -> Void)?
    let keychain = Keychain(service: "me.ss-abramchuk.openVPN-Test", accessGroup: "6Z83F6YM43.keychain-shared")
    
    lazy var vpnAdapter: OpenVPNAdapter = {
        return OpenVPNAdapter().then { $0.delegate = self}
    }()
    lazy var vpnCredentials: OpenVPNCredentials = {
        return OpenVPNCredentials()
    }()
    
    var startHandler: ((Error?) -> Void)?
    var stopHandler: (() -> Void)?
    
    override func startTunnel(options: [String : NSObject]? = nil, completionHandler: @escaping (Error?) -> Void) {
        guard let settings = options?["Settings"] as? Data else {
            let error = PacketTunnelProviderError.fatalError(message: "无法从选项中检索OpenVPN设置")
            completionHandler(error)
            return
        }
        
        print(settings.base64EncodedString())
        
        if let username = protocolConfiguration.username {
            vpnCredentials.username = username
        }
        if let reference = protocolConfiguration.passwordReference {
            do{
                guard let password = try keychain.get(ref: reference) else {
                    throw PacketTunnelProviderError.fatalError(message: "无法从钥匙串中检索密码")
            }
                vpnCredentials.password = password
                
            }catch {
                completionHandler(error)
                return
            }
        }
        do {
            try
                //                vpnAdapter.configure(using: settings)
                vpnAdapter.provide(credentials: vpnCredentials)
            
        } catch {
            completionHandler(error)
            return
        }
        
        startHandler = completionHandler
        vpnAdapter.connect()
    }
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        stopHandler = completionHandler
        vpnAdapter.disconnect()
    }
    
}




extension PacketTunnelProvider: OpenVPNAdapterDelegate{
    func configureTunnel(settings: NEPacketTunnelNetworkSettings, callback: @escaping (OpenVPNAdapterPacketFlow?) -> Void) {
        setTunnelNetworkSettings(settings) { (error) in
            callback(error == nil ? self.packetFlow : nil)
        }
    }
    
    func handle(event: OpenVPNAdapterEvent, message: String?) {
        switch event {
        case .connected://成功连接到VPN服务器
            guard let statrtHandler = startHandler else {
                return
            }
            statrtHandler(nil)
            self.startHandler = nil
        case .disconnected://断开与VPN服务器的连接
            guard let stopHandler = stopHandler else {
                return
            }
            stopHandler()
            self.startHandler = nil
        default:
            break
        }
    }
    
    func handle(error: Error) {
        guard let fatal = (error as NSError).userInfo[OpenVPNAdapterErrorFatalKey] as? Bool, fatal == true else { return  }
        
        if let startHandler = startHandler {
            startHandler(error)
            self.startHandler = nil
        }else{
            cancelTunnelWithError(error)
        }
        
    }
}
