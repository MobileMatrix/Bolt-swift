import Foundation
import NIO
import PackStream

class ReadDataHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer
    
    var dataBuffer: [UInt8] = []
    
    var dataReceivedBlock: (([UInt8]) -> ())?
    
    func channelActive(ctx: ChannelHandlerContext) {
        ctx.fireChannelActive()
    }
    
    func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
        
        defer {
            ctx.fireChannelRead(data)
        }
        
        let buffer = unwrapInboundIn(data)
        let readableBytes = buffer.readableBytes
        
        if readableBytes == 0 {
            print("nothing left to read, close the channel")
            ctx.close(promise: nil)
            return
        }

        let bytes = buffer.getBytes(at: 0, length: readableBytes) ?? []
        
        if readableBytes <= 4 { // It's just a small message, pass it along without further testing
            dataReceivedBlock?(bytes)
            return
        }
        
        self.dataBuffer.append(contentsOf: bytes)
        
        if messageIsTerminated(self.dataBuffer) == false {
            // Didn't end with 00:00, so more bytes should be coming
            return
        }
        
        if messageShouldEndInSummary(self.dataBuffer) && messageEndsInSummary(self.dataBuffer) == false {
            // A longer message should always end in a summary. If not, wait for more data
            return
        }
        
        // By this time we know we got a full message, so pass it back
        let receivedBuffer = self.dataBuffer
        self.dataBuffer = []
        dataReceivedBlock?(receivedBuffer)
    }
    
    func errorCaught(ctx: ChannelHandlerContext, error: Error) {
        print("error: \(error.localizedDescription)")
        ctx.close(promise: nil)
    }
    
    func messageIsTerminated(_ bytes: [UInt8]) -> Bool {
        
        let length = bytes.count
        if length < 2 {
            return false
        }
        
        if bytes[length - 1] != 0 {
            return false
        }

        if bytes[length - 2] != 0 {
            return false
        }

        return true
    }

    func messageShouldEndInSummary(_ bytes: [UInt8]) -> Bool {
        if self.dataBuffer[3] == Connection.CommandResponse.record.rawValue {
            return true
        }
        
        return bytes.count > 256
    }
    
    private func findPositionOfTerminator(in bytes: ArraySlice<UInt8>) -> Int? {
        if bytes.endIndex - bytes.startIndex - 1 < 0 {
            return nil
        }
        
        for i in bytes.startIndex ..< (bytes.endIndex - 1) {
            if bytes[i] == 0 && bytes[i+1] == 0 {
                return i
            }
        }
        
        return nil
    }

    func messageEndsInSummary(_ bytes: [UInt8]) -> Bool {
        
        let byteCount = bytes.count
        let limiter = 400
        let slice = byteCount > limiter ? bytes[(byteCount - limiter)..<byteCount] : bytes[0..<byteCount]
        if  let positionOfTerminator = findPositionOfTerminator(in: slice) {
            let fixedSlice = Array<UInt8>(bytes[(positionOfTerminator+2)..<byteCount])
            if let chunks = try? Response.unchunk(fixedSlice),
                let lastChunk = chunks.last,
                let lastRecord = try? Response.unpack(lastChunk) {
                if lastRecord.category == Response.Category.success {
                    return true
                }
            }
        }
        
        return false
    }

    
}
