import Foundation

// Assuming access to Fuzzilli's internal types like Program, Instruction, ProgramBuilder, Operation, Variable, Type, Fuzzer, etc.
// These are conceptual placeholders based on Fuzzilli's structure.

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

    // Initialize the mutator, providing its name to the superclass.
    // The 'name' property is inherited from the Contributor base class.
    public override init() {
        super.init(name: "InstantiateModuleStencilFixerMutator")
    }

    // This is the main mutation function that subclasses of Mutator must override.
    // It receives the program to mutate, a ProgramBuilder instance, and the Fuzzer instance.
    override public func mutate(_ program: Program, using b: ProgramBuilder, for fuzzer: Fuzzer) -> Program? {
        var callInstrIndex: Int? = nil
        var problematicArgVar: Variable? = nil
        var functionVar: Variable? = nil

        // 1. Find a potential 'instantiateModuleStencil(arg)' call.
        for (i, instr) in program.code.enumerated() {
            // Check if it's a function call with exactly one argument (input(0) is function, input(1) is arg).
            if instr.op.name == "CallFunction" && instr.numInputs == 2 {
                let funcVar = instr.input(0)
                let argVar = instr.input(1)

                // TODO: Add more robust checks if possible:
                //  - Check if funcVar was loaded from LoadGlobal("instantiateModuleStencil").
                //  - Check if Fuzzilli's type analysis suggests argVar might be a Number or Primitive.
                // For this specific mutator, we might assume *any* CallFunction with one argument
                // is a candidate, relying on the next step to find a "problematic" definition.
                callInstrIndex = i
                functionVar = funcVar
                problematicArgVar = argVar
                break // Process the first candidate found
            }
        }

        // If no candidate call instruction was found, bail out.
        guard let callIdx = callInstrIndex,
              let argVar = problematicArgVar,
              let funcVar = functionVar else {
            return nil
        }

        // 2. Find the instruction that defines the problematic argument `argVar`.
        //    We search backwards from the call site.
        var defInstrIndex: Int? = nil
        var definitionInstruction: Instruction? = nil
        for i in (0..<callIdx).reversed() {
            let currentInstr = program.code[i]
            // Check if the instruction at index 'i' defines 'argVar'.
            // Assuming an instruction has at most one primary output variable.
            // Use 'numOutputs == 1' to ensure it has an output, then check 'output'.
            if currentInstr.numOutputs == 1 && currentInstr.output == argVar {
                // TODO: Add check if this definition is likely the source of the problem
                // (e.g., `{} | {}`). This might involve checking the operation type
                // and potentially the inputs to that operation.
                // For now, we assume finding the definition is sufficient cause to try the fix.
                defInstrIndex = i
                definitionInstruction = currentInstr
                break
            }
        }

        // If we couldn't find the definition of the argument before the call, bail out.
        guard let defIdx = defInstrIndex, let defInstr = definitionInstruction else {
            return nil
        }

        // 3. Build the new program using the provided ProgramBuilder 'b'.
        //    The 'b.adopting(from: program)' block allows easy use of variables from the original program.
        b.adopting(from: program) {

            // Copy instructions from the beginning up to (but not including) the definition.
            for i in 0..<defIdx {
                b.append(program.code[i])
            }

            // --- Start: Insert the fix code (negative test case logic) ---
            // This variable will hold the safe stencil or placeholder object.
            // Use b.nextVariable() or similar if harnessVariable() is not what's intended
            // or if it needs to be a temporary variable not tied to harness.
            // Assuming harnessVariable() is suitable for a value that might be used by harness/environment.
            let v_validStencil = b.harnessVariable() // Or b.nextVariable() if more appropriate

            // Try block to attempt using compileModule
            b.beginTry()
                let moduleSourceStr = "export let x = 1;"
                let v_moduleSource = b.loadString(moduleSourceStr)
                // Assume 'compileModule' is available as a builtin or global
                let v_compileModule = b.loadBuiltin("compileModule") // Adjust if it's a global: b.loadGlobal("compileModule")
                // Call compileModule and attempt to assign the result to v_validStencil
                let v_stencilAttempt = b.callFunction(v_compileModule, withArgs: [v_moduleSource])
                b.reassign(v_validStencil, to: v_stencilAttempt)
            // Catch block if compileModule fails
            let v_e1 = b.beginCatch() // v_e1 holds the exception object
                // Create a simple placeholder object: { stub: true }
                let v_placeholder = b.createObject(with: [:]) // Creates an empty object
                let v_true = b.loadBoolean(true)
                b.storeProperty("stub", as: v_true, on: v_placeholder) // Corrected: storeProperty("stub", as: v_true, on: v_placeholder) or similar
                                                                     // Fuzzilli's API might be b.storeProperty(v_placeholder, "stub", v_true)
                                                                     // The original code was: b.storeProperty("stub", on: v_placeholder, with: v_true)
                                                                     // Let's assume the original API was correct for storeProperty.

                // Assign the placeholder to v_validStencil
                b.reassign(v_validStencil, to: v_placeholder)
                // Print an informative message (optional, but matches negative case)
                // Assume 'print' is available as a builtin or global
                let v_print = b.loadBuiltin("print") // Adjust if it's a global
                let v_errMsg1 = b.loadString("compileModule not available or failed, using placeholder object. Error: ")
                // Concatenate the error message and the exception (requires BinaryOperation Add for strings)
                // This assumes the exception object v_e1 can be meaningfully concatenated or converted to string by 'Add'.
                // Consider b.typeOf(v_e1) and then b.toString(v_e1) if direct addition is problematic.
                let v_errorStr = b.binary(v_errMsg1, v_e1, with: .Add)
                b.callFunction(v_print, withArgs: [v_errorStr])
            b.endTryCatch() // End of the compileModule try/catch block


            // Try block to call instantiateModuleStencil with the potentially valid stencil/object
            b.beginTry()
                // Get the original function variable (the one holding instantiateModuleStencil)
                // We need to adopt it into the current builder's scope.
                let v_instantiateFunc = b.adopt(funcVar)
                // Call the function with the safe variable 'v_validStencil'
                b.callFunction(v_instantiateFunc, withArgs: [v_validStencil])
            // Catch block if instantiateModuleStencil still throws an error
            let v_e2 = b.beginCatch() // v_e2 holds the exception object
                // Print an informative message (optional, but matches negative case)
                let v_print2 = b.loadBuiltin("print") // Adjust if it's a global
                let v_errMsg2 = b.loadString("instantiateModuleStencil threw an error (as might be expected): ")
                // Concatenate the error message and the exception
                let v_errorStr2 = b.binary(v_errMsg2, v_e2, with: .Add)
                b.callFunction(v_print2, withArgs: [v_errorStr2])
            b.endTryCatch() // End of the instantiateModuleStencil try/catch block
            // --- End: Insert the fix code ---


            // Copy instructions that were originally between the definition and the call.
            for i in (defIdx + 1)..<callIdx {
                b.append(program.code[i])
            }

            // Append the original defining instruction(s) *after* the fix.
            // If the problematic value was created over multiple instructions, append them all.
            // Here we assume 'defInstr' is the single instruction defining 'argVar'.
            // This also means its inputs must have been defined before defIdx or adopted.
            b.append(defInstr)
            // If defInstr used inputs defined *immediately* before it (like the {} objects for `{} | {}`),
            // those instructions also need to be moved here to maintain correctness if they are part of
            // the "problematic pattern" and not general setup code.
            // The current logic copies instructions from 0..<defIdx, then inserts the fix,
            // then copies (defIdx + 1)..<callIdx, then appends defInstr.
            // This means if defInstr relies on instructions immediately preceding it (e.g., v1=Create, v2=Create, v3=BinOp v1,v2),
            // and defIdx points to BinOp, then CreateObject instructions (v1, v2) would have been copied
            // *before* the fix. This seems correct for the described pattern.


            // Copy the remaining instructions from the original program, skipping the original call.
            for i in (callIdx + 1)..<program.code.count {
                 b.append(program.code[i])
            }
        } // End adoption scope

        // Return the newly constructed program.
        return b.finalize()
    }
}