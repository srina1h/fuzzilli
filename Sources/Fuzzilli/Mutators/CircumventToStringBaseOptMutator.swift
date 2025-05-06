import Foundation

// Assuming access to Fuzzilli's internal types like Program, Instruction, ProgramBuilder, Operation, Variable, Type, Fuzzer, etc.
// These are conceptual placeholders based on Fuzzilli's structure.
// Also assuming Fuzzilli's ProgramBuilder has a method like:
// buildTryCatch(_ tryBody: () -> Void, _ catchBody: (Variable) -> Void)

/// A very specific mutator designed to transform a crashing pattern involving
/// `instantiateModuleStencil` with a non-object argument (like the result of `{} | {}`)
/// into a non-crashing version that attempts to use `compileModule` or a placeholder object.
///
/// It looks for a sequence like:
/// ```
/// v1 = CreateObject() // {}
/// v2 = CreateObject() // {}
/// v3 = BinaryOperation '|', v1, v2 // Result is 0 (number)
/// ... possibly other instructions ...
/// v4 = LoadGlobal("instantiateModuleStencil") or similar
/// CallFunction v4, [v3] // Crash occurs here
/// ```
/// And transforms it into the structure provided in the negative test case:
/// ```
/// // ... instructions before v1 definition ...
///
/// // Block to create 'validStencil' using compileModule or a placeholder
/// v_validStencil = ... // Result of try/catch logic
///
/// // Try/catch block calling instantiateModuleStencil with the safe object
/// Try
///     v_instantiateFunc = LoadGlobal("instantiateModuleStencil") // Or adopt original func var
///     CallFunction v_instantiateFunc, [v_validStencil]
/// Catch e2
///     // Print error
/// EndTryCatch
///
/// // ... instructions between v3 definition and the original CallFunction ...
///
/// v1 = CreateObject() // Original definition instructions are moved here
/// v2 = CreateObject()
/// v3 = BinaryOperation '|', v1, v2 // Original problematic op, now unused by the call
///
/// // ... instructions after the original CallFunction ...
/// ```
public class InstantiateModuleStencilFixerMutator: Mutator {

    public init() {
        super.init(name: "InstantiateModuleStencilFixerMutator")
    }

    override public func mutate(_ program: Program, using b: ProgramBuilder, for fuzzer: Fuzzer) -> Program? {
        var callInstrIndex: Int? = nil
        var problematicArgVar: Variable? = nil
        var functionVar: Variable? = nil

        // 1. Find a potential 'instantiateModuleStencil(arg)' call.
        for (i, instr) in program.code.enumerated() {
            if instr.op.name == "CallFunction" && instr.numInputs == 2 {
                let funcVar = instr.input(0)
                let argVar = instr.input(1)
                callInstrIndex = i
                functionVar = funcVar
                problematicArgVar = argVar
                break 
            }
        }

        guard let callIdx = callInstrIndex,
              let argVar = problematicArgVar,
              let funcVar = functionVar else {
            return nil
        }

        // 2. Find the instruction that defines the problematic argument `argVar`.
        var defInstrIndex: Int? = nil
        var definitionInstruction: Instruction? = nil
        for i in (0..<callIdx).reversed() {
            let currentInstr = program.code[i]
            if currentInstr.numOutputs == 1 && currentInstr.output == argVar {
                defInstrIndex = i
                definitionInstruction = currentInstr
                break
            }
        }

        guard let defIdx = defInstrIndex, let defInstr = definitionInstruction else {
            return nil
        }

        // 3. Build the new program using the provided ProgramBuilder 'b'.
        b.adopting(from: program) {

            // Copy instructions from the beginning up to (but not including) the definition.
            for i in 0..<defIdx {
                b.append(program.code[i])
            }

            // --- Start: Insert the fix code (negative test case logic) ---
            let v_validStencil = b.nextVariable() 

            // Try block to attempt using compileModule
            // Assuming Fuzzilli's API is: b.buildTryCatch(tryBodyClosure, catchBodyClosure)
            b.buildTryCatch({
                // This is the TRY body
                let moduleSourceStr = "export let x = 1;"
                let v_moduleSource = b.loadString(moduleSourceStr)
                let v_compileModule = b.loadBuiltin("compileModule") // Adjust if it's a global
                let v_stencilAttempt = b.callFunction(v_compileModule, withArgs: [v_moduleSource])
                b.reassign(v_validStencil, to: v_stencilAttempt)
            }, { v_e1 in
                // This is the CATCH body; v_e1 is the exception variable provided by buildTryCatch
                let v_placeholder = b.createObject(with: [:]) 
                let v_true = b.loadBoolean(true)
                // Assuming this storeProperty API is correct for your Fuzzilli version
                b.storeProperty("stub", on: v_placeholder, with: v_true) 

                b.reassign(v_validStencil, to: v_placeholder)
                
                let v_print = b.loadBuiltin("print") // Adjust if it's a global
                let v_errMsg1 = b.loadString("compileModule not available or failed, using placeholder object. Error: ")
                let v_errorStr = b.binary(v_errMsg1, v_e1, with: .Add) 
                b.callFunction(v_print, withArgs: [v_errorStr])
            }) // End of the compileModule try/catch block


            // Try block to call instantiateModuleStencil with the potentially valid stencil/object
            b.buildTryCatch({
                // This is the TRY body
                let v_instantiateFunc = b.adopt(funcVar)
                b.callFunction(v_instantiateFunc, withArgs: [v_validStencil])
            }, { v_e2 in
                // This is the CATCH body; v_e2 is the exception variable
                let v_print2 = b.loadBuiltin("print") // Adjust if it's a global
                let v_errMsg2 = b.loadString("instantiateModuleStencil threw an error (as might be expected): ")
                let v_errorStr2 = b.binary(v_errMsg2, v_e2, with: .Add)
                b.callFunction(v_print2, withArgs: [v_errorStr2])
            }) // End of the instantiateModuleStencil try/catch block
            // --- End: Insert the fix code ---

            // Copy instructions that were originally between the definition and the call.
            for i in (defIdx + 1)..<callIdx {
                b.append(program.code[i])
            }

            // Append the original defining instruction(s) *after* the fix.
            b.append(defInstr)

            // Copy the remaining instructions from the original program, skipping the original call.
            for i in (callIdx + 1)..<program.code.count {
                 b.append(program.code[i])
            }
        } // End adoption scope

        return b.finalize()
    }
}
