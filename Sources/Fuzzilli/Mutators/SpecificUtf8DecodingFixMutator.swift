

public class SpecificUtf8DecodingFixMutator: BaseMutator {

    public init() {

        super.init(name: "SpecificUtf8DecodingFixMutator")

    }



    public override func mutate(_ program: Program, _ b: ProgramBuilder, _ n: Int) -> MutationResult {

        // This mutator ignores the input program and deterministically generates

        // the FuzzIL code corresponding to the "negative test case".

        b.reset()

        buildNegativeTestCase(b)

        // Return .success as we generated a new program structure.

        // Depending on Fuzzilli's exact usage, if this should only run once

        // or under specific conditions, logic would be needed here or in the

        // fuzzer configuration to select this mutator appropriately.

        return .success

    }



    private func buildNegativeTestCase(_ b: ProgramBuilder) {

        // Build FuzzIL code for: function runCircumventionTest() { ... }

        let runCircumventionTest = b.definePlainFunction(signature: FunctionSignature(withParameterCount: 0)) { _ in



            // Build FuzzIL code for: Test case 1 (Mid-String Error)

            b.buildTryCatchFinally(tryBody: {

                // const utf8_mid_error = new Uint8Array([0xF0, 0x90, 0x80, 0x41]);

                let f0 = b.loadInt(0xF0)

                let nine0 = b.loadInt(0x90)

                let eight0_1 = b.loadInt(0x80) // Renamed to avoid conflict later

                let four1 = b.loadInt(0x41)

                let byteArray1 = b.createArray(with: [f0, nine0, eight0_1, four1])

                let uint8ArrayCls1 = b.loadBuiltin("Uint8Array") // Renamed to avoid conflict

                let utf8_mid_error = b.construct(uint8ArrayCls1, withArgs: [byteArray1])



                // const utf16_mid_error = new TextDecoder("utf-8", { fatal: false }).decode(utf8_mid_error);

                let utf8Str1 = b.loadString("utf-8") // Renamed

                let fatalFalse1 = b.loadBool(false) // Renamed

                let options1 = b.createObject(with: ["fatal": fatalFalse1])

                let textDecoderCls1 = b.loadBuiltin("TextDecoder") // Renamed

                let decoder1 = b.construct(textDecoderCls1, withArgs: [utf8Str1, options1])

                let decodeMethod1 = b.loadProperty(decoder1, "decode")

                let utf16_mid_error = b.callMethod(decodeMethod1, on: decoder1, withArgs: [utf8_mid_error])



                // const expected_mid_error = "\uFFFDA";

                let expected_mid_error = b.loadString("\u{FFFD}A")



                // if (utf16_mid_error !== expected_mid_error) { console.error(...) }

                let comparison1 = b.compare(utf16_mid_error, expected_mid_error, with: .strictNotEqual)

                b.buildIf(comparison1) {

                    let console1 = b.loadBuiltin("console") // Renamed

                    let errorFunc1 = b.loadProperty(console1, "error") // Renamed

                    let errMsg1 = b.loadString("Test Failed (Mid-String Error): Expected '\u{FFFD}A', got '...'") // More specific msg stub

                    // In a real scenario, you might build the string dynamically if needed, but static is simpler here.

                    b.callFunction(errorFunc1, withArgs: [errMsg1]) // Pass only message for simplicity like target

                }

            }, catchBody: { errorVar1 in // Renamed

                // console.error("Test Failed (Mid-String Error): Unexpected exception", e);

                let consoleCatch1 = b.loadBuiltin("console") // Renamed

                let errorFuncCatch1 = b.loadProperty(consoleCatch1, "error") // Renamed

                let errMsgCatch1 = b.loadString("Test Failed (Mid-String Error): Unexpected exception") // Renamed

                b.callFunction(errorFuncCatch1, withArgs: [errMsgCatch1, errorVar1])

            })



            // Build FuzzIL code for: Test case 2 (Valid String)

            b.buildTryCatchFinally(tryBody: {

                // const validString = "Valid UTF-8 String 😊";

                let validString = b.loadString("Valid UTF-8 String 😊")



                // const utf8_valid = new TextEncoder().encode(validString);

                let textEncoderCls = b.loadBuiltin("TextEncoder")

                let encoder = b.construct(textEncoderCls)

                let encodeMethod = b.loadProperty(encoder, "encode")

                let utf8_valid = b.callMethod(encodeMethod, on: encoder, withArgs: [validString])



                // const utf16_valid = new TextDecoder("utf-8", { fatal: true }).decode(utf8_valid);

                let utf8Str2 = b.loadString("utf-8") // Renamed

                let fatalTrue = b.loadBool(true)

                let options2 = b.createObject(with: ["fatal": fatalTrue])

                let textDecoderCls2 = b.loadBuiltin("TextDecoder") // Renamed

                let decoder2 = b.construct(textDecoderCls2, withArgs: [utf8Str2, options2])

                let decodeMethod2 = b.loadProperty(decoder2, "decode")

                let utf16_valid = b.callMethod(decodeMethod2, on: decoder2, withArgs: [utf8_valid])



                // if (utf16_valid !== validString) { console.error(...) }

                let comparison2 = b.compare(utf16_valid, validString, with: .strictNotEqual)

                b.buildIf(comparison2) {

                    let console2 = b.loadBuiltin("console") // Renamed

                    let errorFunc2 = b.loadProperty(console2, "error") // Renamed

                    let errMsg2 = b.loadString("Test Failed (Valid String): Expected '...', got '...'") // More specific msg stub

                    b.callFunction(errorFunc2, withArgs: [errMsg2]) // Pass only message

                }

            }, catchBody: { errorVar2 in // Renamed

                // console.error("Test Failed (Valid String): Unexpected exception", e);

                let consoleCatch2 = b.loadBuiltin("console") // Renamed

                let errorFuncCatch2 = b.loadProperty(consoleCatch2, "error") // Renamed

                let errMsgCatch2 = b.loadString("Test Failed (Valid String): Unexpected exception") // Renamed

                b.callFunction(errorFuncCatch2, withArgs: [errMsgCatch2, errorVar2])

            })



            // Build FuzzIL code for: Test case 3 (Invalid Start Byte)

             b.buildTryCatchFinally(tryBody: {

                // const utf8_invalid_start = new Uint8Array([0x80, 0x42]);

                let eight0_3 = b.loadInt(0x80) // Renamed

                let four2 = b.loadInt(0x42)

                let byteArray3 = b.createArray(with: [eight0_3, four2])

                let uint8ArrayCls3 = b.loadBuiltin("Uint8Array") // Renamed

                let utf8_invalid_start = b.construct(uint8ArrayCls3, withArgs: [byteArray3])



                // const utf16_invalid_start = new TextDecoder("utf-8", { fatal: false }).decode(utf8_invalid_start);

                let utf8Str3 = b.loadString("utf-8") // Renamed

                let fatalFalse3 = b.loadBool(false) // Renamed

                let options3 = b.createObject(with: ["fatal": fatalFalse3])

                let textDecoderCls3 = b.loadBuiltin("TextDecoder") // Renamed

                let decoder3 = b.construct(textDecoderCls3, withArgs: [utf8Str3, options3])

                let decodeMethod3 = b.loadProperty(decoder3, "decode")

                let utf16_invalid_start = b.callMethod(decodeMethod3, on: decoder3, withArgs: [utf8_invalid_start])



                // const expected_invalid_start = "\uFFFDB";

                let expected_invalid_start = b.loadString("\u{FFFD}B")



                // if (utf16_invalid_start !== expected_invalid_start) { console.error(...) }

                let comparison3 = b.compare(utf16_invalid_start, expected_invalid_start, with: .strictNotEqual)

                b.buildIf(comparison3) {

                    let console3 = b.loadBuiltin("console") // Renamed

                    let errorFunc3 = b.loadProperty(console3, "error") // Renamed

                    let errMsg3 = b.loadString("Test Failed (Invalid Start Byte): Expected '\u{FFFD}B', got '...'") // More specific msg stub

                    b.callFunction(errorFunc3, withArgs: [errMsg3]) // Pass only message

                }

            }, catchBody: { errorVar3 in // Renamed

                // console.error("Test Failed (Invalid Start Byte): Unexpected exception", e);

                let consoleCatch3 = b.loadBuiltin("console") // Renamed

                let errorFuncCatch3 = b.loadProperty(consoleCatch3, "error") // Renamed

                let errMsgCatch3 = b.loadString("Test Failed (Invalid Start Byte): Unexpected exception") // Renamed

                b.callFunction(errorFuncCatch3, withArgs: [errMsgCatch3, errorVar3])

            })

        } // End of function definition: runCircumventionTest



        // Build FuzzIL code for: runCircumventionTest();

        b.callFunction(runCircumventionTest, withArgs: [])

    }

}
