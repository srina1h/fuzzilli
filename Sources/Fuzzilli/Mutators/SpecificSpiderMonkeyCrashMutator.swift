

// This mutator is specifically designed to transform the positive test case

// related to the SpiderMonkey assertion failure (commit 04f7743d9469)

// into the negative test case described in the prompt.

// It looks for the specific pattern:

// 1. newGlobal() -> v1

// 2. v1.enableShellAllocationMetadataBuilder()

// 3. A function definition (f3)

// 4. Inside f3: v1.load -> v5, v5.toString = f3, [Return] v5(v5)

// 5. A call to f3()

// It then removes the enableShellAllocationMetadataBuilder call and wraps

// the recursive call (v5(v5)) and its potential Return inside a try-catch block.

// NOTE: This is a highly specialized mutator and likely brittle.

// It assumes a specific FuzzIL representation of the JavaScript code.

public class SpecificSpiderMonkeyCrashMutator: BaseMutator {



    init() {

        super.init(name: "SpecificSpiderMonkeyCrashMutator")

    }



    override public func mutate(_ program: Program, using b: ProgramBuilder) -> Result {

        // Indices and variables to find

        var newGlobalInstIndex: Int? = nil

        var v1: Variable? = nil // result of newGlobal() call

        var enableShellCallIndex: Int? = nil

        var f3DefIndex: Int? = nil

        var v3: Variable? = nil // The function variable (f3)

        // We don't strictly need f3V5LoadIndex or f3ToStringSetIndex for the rebuild, but finding them helps confirm the pattern

        var v5: Variable? = nil // result of v1.load

        var f3RecursiveCallIndex: Int? = nil

        var recursiveCallResult: Variable? = nil // Output of the recursive call, if captured

        var f3ReturnIndex: Int? = nil // Optional index of the 'Return' instruction if it returns the recursive call result

        var f3EndDefIndex: Int? = nil

        var f3CallIndex: Int? = nil // Index of the final f3() call



        // --- Pass 1: Find the pattern ---

        // This loop attempts to find the specific sequence of instructions corresponding

        // to the positive test case structure.

        for (idx, instr) in program.code.enumerated() {

            // Look for v1 = newGlobal() pattern

            if newGlobalInstIndex == nil && instr.op is LoadBuiltin && instr.op.opName == "LoadBuiltin 'newGlobal'" {

                if idx + 1 < program.code.count {

                    let nextInstr = program.code[idx + 1]

                    if nextInstr.op is CallFunction && nextInstr.numInputs == 1 && nextInstr.input(0) == instr.output {

                        newGlobalInstIndex = idx // Mark the LoadBuiltin index

                        v1 = nextInstr.output // Store the variable holding the global object

                    }

                }

            // Look for v1.enableShellAllocationMetadataBuilder()

            } else if v1 != nil && enableShellCallIndex == nil && instr.op is CallMethod {

                 if let methodName = instr.opParam as? String, methodName == "enableShellAllocationMetadataBuilder", instr.input(0) == v1 {

                    enableShellCallIndex = idx

                 }

            // Look for function f3() { ... } definition

            } else if enableShellCallIndex != nil && f3DefIndex == nil && instr.op is BeginFunctionDefinition {

                f3DefIndex = idx

                v3 = instr.output // Store the function variable

            // Look for instructions inside f3

            } else if f3DefIndex != nil && f3EndDefIndex == nil { // Only look between Begin/End FunctionDefinition

                 // Look for v5 = v1.load

                 if instr.op is LoadProperty && instr.opParam is String && instr.opParam as! String == "load" && instr.input(0) == v1 {

                    v5 = instr.output // Store the variable holding v1.load

                 // Look for v5.toString = f3

                 } else if v5 != nil && instr.op is SetProperty && instr.opParam is String && instr.opParam as! String == "toString" && instr.input(0) == v5 && instr.input(1) == v3 {

                    // Found it, don't need to store index necessarily

                 // Look for the recursive call v5(v5)

                 } else if v5 != nil && instr.op is CallFunction && instr.numInputs == 2 && instr.input(0) == v5 && instr.input(1) == v5 {

                    f3RecursiveCallIndex = idx

                    if instr.hasOutput {

                        recursiveCallResult = instr.output // Store the result variable if it exists

                    }

                 // Look for return <result_of_recursive_call> (optional)

                 } else if f3RecursiveCallIndex != nil && recursiveCallResult != nil && instr.op is Return && instr.numInputs == 1 && instr.input(0) == recursiveCallResult {

                    f3ReturnIndex = idx

                 // Look for end of function definition

                 } else if instr.op is EndFunctionDefinition {

                    f3EndDefIndex = idx

                 }

            // Look for the final call f3()

            } else if f3EndDefIndex != nil && f3CallIndex == nil && instr.op is CallFunction && instr.numInputs == 1 && instr.input(0) == v3 {

                f3CallIndex = idx

            }

        }



        // --- Check if the full pattern was found ---

        // All parts including the recursive call inside the function must be found.

        // The return instruction is optional. The final call `f3()` should also exist.

        guard let v1 = v1, // Ensure v1 was found

              let enableShellCallIdx = enableShellCallIndex,

              let f3DefIdx = f3DefIndex,

              let v3 = v3, // Ensure function variable was found

              let v5 = v5, // Ensure v5 (v1.load) was found

              let f3RecursiveCallIdx = f3RecursiveCallIndex,

              // f3ReturnIndex is optional, recursiveCallResult might be nil if call has no output

              let f3EndDefIdx = f3EndDefIndex,

              let _ = f3CallIndex // Ensure the final call f3() was found

        else {

            // The specific pattern required for this mutator was not found in the program.

            return .failure

        }



        // --- Pass 2: Rebuild the program with modifications ---

        // Use adopting to correctly map variables from the old program to the new one.

        b.adopting(from: program) {

            // Copy instructions before the 'enableShellAllocationMetadataBuilder' call

            for i in 0..<enableShellCallIdx {

                b.adopt(program.code[i])

            }



            // Skip the 'enableShellAllocationMetadataBuilder' call (instruction at enableShellCallIdx)



            // Copy instructions between the removed call and the function definition

            for i in (enableShellCallIdx + 1)..<f3DefIdx {

                 b.adopt(program.code[i])

            }



            // Adopt the BeginFunctionDefinition instruction

            b.adopt(program.code[f3DefIdx])



            // Copy instructions inside the function up to the recursive call

            for i in (f3DefIdx + 1)..<f3RecursiveCallIdx {

                b.adopt(program.code[i])

            }



            // --- Insert the try-catch block ---

            b.beginTry()



            // Re-emit the recursive call instruction inside the try block

            let recursiveCallInstr = program.code[f3RecursiveCallIdx]

            b.adopt(recursiveCallInstr) // Adopting handles variable mapping



            // Re-emit the return instruction if it existed and returned the recursive call's result

            if let returnIdx = f3ReturnIndex {

                // We previously verified that this return uses recursiveCallResult

                let returnInstr = program.code[returnIdx]

                b.adopt(returnInstr)

            }

            // If there was no return instruction associated with the call, do nothing extra here.



            b.beginCatch()

            // Add a simple placeholder instruction in the catch block, as it cannot be empty.

            // We don't need the result, so we can just load undefined.

            b.loadUndefined()

            b.endTryCatch()

            // --- End try-catch block ---



            // Copy remaining instructions inside the function *after* the original call/return block

            // Start copying from the instruction after the recursive call, or after the return if it existed.

            let startIndexAfterTryCatch = (f3ReturnIndex ?? f3RecursiveCallIdx) + 1

            for i in startIndexAfterTryCatch..<f3EndDefIdx {

                 b.adopt(program.code[i])

            }



            // Adopt the EndFunctionDefinition instruction

            b.adopt(program.code[f3EndDefIdx])



            // Copy all instructions after the function definition until the end of the program

            for i in (f3EndDefIdx + 1)..<program.code.count {

                 b.adopt(program.code[i])

            }

        } // End adopting block



        // If we successfully rebuilt the program in the builder, return success.

        return .success

    }

}
