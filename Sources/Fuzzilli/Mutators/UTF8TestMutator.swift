import Foundation

/// A mutator that transforms a positive test case into a negative test case for UTF-8 decoding.
/// The positive test case tests basic UTF-8 decoding behavior, while the negative test case
/// tests more complex scenarios and error handling.
public class UTF8TestMutator: BaseInstructionMutator {
    public init() {
        super.init(name: "UTF8TestMutator")
    }
    
    public override func canMutate(_ instr: Instruction) -> Bool {
        // Check if this is a function definition that matches our positive test case pattern
        if case .beginPlainFunction(let op) = instr.op {
            // Look for the specific pattern in the function body
            let code = instr.innerOutputs
            for i in 0..<code.count {
                if case .loadString(let str) = instr.op {
                    if str.contains("TextEncoder") && str.contains("TextDecoder") {
                        return true
                    }
                }
            }
        }
        return false
    }
    
    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {
        // Create the negative test case function
        b.buildPlainFunction(with: .parameters(n: 0)) { _ in
            // Test case 1: Use the problematic sequence but ensure it's followed by a valid character
            b.buildTryCatch { b in
                let utf8_mid_error = b.createArray(with: [b.loadInt(0xF0), b.loadInt(0x90), b.loadInt(0x80), b.loadInt(0x41)])
                let utf16_mid_error = b.callMethod("decode", on: b.createObjectLiteral(with: [
                    "encoding": b.loadString("utf-8")
                ]), withArgs: [utf8_mid_error])
                b.callMethod("encode", on: b.createObjectLiteral(with: [
                    "encoding": b.loadString("utf-16le")
                ]), withArgs: [utf16_mid_error])
            } catch: { b in
                b.print(b.loadString("Caught error: "), b)
            }
            
            // Test case 2: Use only well-formed UTF-8 strings
            b.emit(BeginTry())
            let validString = b.loadString("Valid UTF-8 String \u{1F60A}")
            let utf8_valid = b.callMethod("encode", on: b.createNamedVariable(forBuiltin: "TextEncoder"), withArgs: [validString])
            let utf16_valid = b.callMethod("decode", on: b.createObjectLiteral(with: [
                "fatal": b.loadBool(true)
            ]), withArgs: [utf8_valid])
            
            b.beginIf(b.compare(utf16_valid, validString, with: .notEqual))
            b.callMethod("error", on: b.createNamedVariable(forBuiltin: "console"), withArgs: [
                b.loadString("Test Failed (Valid String): Expected '\(validString)', got '\(utf16_valid)'")
            ])
            b.endIf()
            b.emit(EndTryCatchFinally())
            
            // Test case 3: Use a different kind of ill-formed sequence not at the end
            b.emit(BeginTry())
            let utf8_invalid_start = b.createArray(with: [b.loadInt(0x80), b.loadInt(0x42)])
            let utf16_invalid_start = b.callMethod("decode", on: b.createObjectLiteral(with: [
                "fatal": b.loadBool(false)
            ]), withArgs: [utf8_invalid_start])
            let expected_invalid_start = b.loadString("\u{FFFD}B")
            
            b.beginIf(b.compare(utf16_invalid_start, expected_invalid_start, with: .notEqual))
            b.callMethod("error", on: b.createNamedVariable(forBuiltin: "console"), withArgs: [
                b.loadString("Test Failed (Invalid Start Byte): Expected '\u{FFFD}B', got '\(utf16_invalid_start)'")
            ])
            b.endIf()
            b.emit(EndTryCatchFinally())
        }
        
        // Call the function
        b.callFunction(b.createNamedVariable(forBuiltin: "runCircumventionTest"), withArgs: [])
    }
}
