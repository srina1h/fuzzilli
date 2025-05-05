

/// A mutator that targets a specific JavaScript pattern involving computed static property keys

/// containing both a class definition and a function definition/assignment.

/// It wraps the computed key logic within an Immediately Invoked Anonymous Function Expression (IIAFE)

/// to work around potential engine bugs (like the one observed in Firefox for Babel-generated code).

///

/// Specifically, it transforms code like:

/// ```javascript

/// let capturedPrivateAccess;

/// class A {

///   static #x = 42;

///   static [(class {}, capturedPrivateAccess = () => A.#x)]; // Problematic computed key

/// }

/// console.log(capturedPrivateAccess());

/// ```

/// Into:

/// ```javascript

/// let capturedPrivateAccess;

/// class A {

///   static #x = 42;

///   static [(() => {

///     class Inner {} // Original class definition moved inside

///     capturedPrivateAccess = () => A.#x; // Original assignment moved inside

///     return "computedKey"; // Return a value to be used as the key

///   })()]; // IIAFE provides the key

/// }

/// console.log(capturedPrivateAccess());

/// ```

public class ComputedKeyClassDefFuncAssignWrapperMutator: BaseInstructionMutator {



    public init() {

        super.init(name: "ComputedKeyClassDefFuncAssignWrapperMutator", maxSimultaneousMutations: 1)

    }



    public override func canMutate(_ instr: Instruction) -> Bool {

        // This mutator targets the BeginComputedProperty instruction specifically

        // when it appears in the context of a static class property definition.

        return instr.op is BeginComputedProperty

    }



    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {

        guard instr.op is BeginComputedProperty else { return }

        let beginComputedPropertyIdx = b.indexOf(instr)



        // The pattern usually occurs after BeginClassDefinition and LoadUndefined (for static fields)

        guard beginComputedPropertyIdx >= 2 else { return }



        let loadUndefinedInstr = b.code[beginComputedPropertyIdx - 1]

        let beginClassDefInstr = b.code[beginComputedPropertyIdx - 2]



        // Check if the preceding instructions match the static property context.

        guard loadUndefinedInstr.op is LoadUndefined,

              beginClassDefInstr.op is BeginClassDefinition else {

            return

        }



        // Scan forward to find the matching EndComputedProperty and analyze the content.

        var depth = 1

        var endComputedPropertyIdx = -1

        var containsClassDef = false

        var containsFuncDef = false

        var originalInstructionsInBlock: [Instruction] = []



        for i in (beginComputedPropertyIdx + 1)..<b.code.count {

            let currentInstr = b.code[i]



            if currentInstr.op is BeginComputedProperty {

                depth += 1

            } else if currentInstr.op is EndComputedProperty {

                depth -= 1

                if depth == 0 {

                    endComputedPropertyIdx = i

                    break

                }

            }



            // Heuristically check if the block contains both class and function definitions.

            // This targets the specific pattern causing issues.

            if depth == 1 { // Only check top-level instructions within this block

                 if currentInstr.op is BeginClassDefinition {

                    containsClassDef = true

                }

                if currentInstr.op is BeginFunctionDefinition {

                    containsFuncDef = true

                }

                originalInstructionsInBlock.append(currentInstr)

            }

        }



        // Ensure the block structure and content match the target pattern.

        guard endComputedPropertyIdx != -1, containsClassDef, containsFuncDef else {

            return

        }



        b.trace("Applying ComputedKeyClassDefFuncAssignWrapperMutator at index \(beginComputedPropertyIdx)")



        // Keep the original Begin/End ComputedProperty operations but modify the content.

        let beginComputedPropertyOp = instr.op

        let endComputedPropertyOp = b.code[endComputedPropertyIdx].op



        // Define the signature for the wrapper IIAFE.

        // It takes no arguments and returns something (the computed key).

        let wrapperFuncSignature = Signature.forFunction(withParameters: [], returning: .plain(.anything))

        let wrapperFuncVar = b.defineVariable(for: .function())



        // Start building the replacement instruction sequence.

        var replacementCode: [Instruction] = []



        // 1. BeginComputedProperty (same as original)

        replacementCode.append(Instruction(beginComputedPropertyOp))



        // 2. Define the IIAFE

        replacementCode.append(Instruction(BeginFunctionDefinition(signature: wrapperFuncSignature, isStrict: b.currentCode.context.contains(.strict)), output: wrapperFuncVar))



        // 3. Adopt and place the original instructions inside the IIAFE.

        for originalInstr in originalInstructionsInBlock {

            // Adopting ensures variables are correctly mapped to the new context.

            replacementCode.append(b.adopt(originalInstr))

        }



        // 4. Add an explicit return statement to provide the computed key value.

        let computedKeyValue = b.loadString("computedKey") // Use a string as the key.

        replacementCode.append(Instruction(Return(), inputs: [computedKeyValue]))



        // 5. End the IIAFE definition.

        replacementCode.append(Instruction(EndFunctionDefinition()))



        // 6. Call the IIAFE immediately. The result is the computed key.

        let callResultVar = b.callFunction(wrapperFuncVar, withArgs: [])



        // 7. EndComputedProperty, using the result of the IIAFE call as the key.

        replacementCode.append(Instruction(endComputedPropertyOp, inputs: [callResultVar]))



        // Replace the original instruction block (BeginComputedProperty to EndComputedProperty)

        // with the newly constructed sequence.

        b.replaceInstructionBlock(from: beginComputedPropertyIdx, to: endComputedPropertyIdx, with: replacementCode)

    }

}
