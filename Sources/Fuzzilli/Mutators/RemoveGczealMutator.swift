

// A mutator specifically designed to remove gczeal calls

// based on the observation that they trigger GC-related crashes

// in certain JavaScript engine scenarios, particularly involving debuggers.

public class RemoveGczealMutator: BaseMutator {



    public init() {

        super.init(name: "RemoveGczealMutator")

    }



    // This mutator works on the entire program structure.

    public override func mutate(_ program: Program, using b: ProgramBuilder, for fuzzer: Fuzzer) -> Program? {

        var modified = false



        b.adopting(from: program) {

            // Iterate over all instructions in the original program

            for instr in program.code {

                var isGczealCall = false



                // Check if the instruction is a function call

                if instr.op is CallFunction || instr.op is CallFunctionWithSpread {

                    // Check if the function being called is 'gczeal'

                    // This typically involves checking the instruction that defines the function variable.

                    let functionVar = instr.input(0)

                    if let definingInstruction = program.findDef(of: functionVar) {

                        // Common pattern: gczeal is loaded as a builtin

                        if let loadBuiltin = definingInstruction.op as? LoadBuiltin {

                            if loadBuiltin.builtinName == "gczeal" {

                                isGczealCall = true

                            }

                        }

                        // Less common, but possible: gczeal assigned to a variable first

                        // This would require more complex tracking, but LoadBuiltin covers the example case.

                    }

                }



                // If the instruction is identified as a gczeal call, skip it.

                if isGczealCall {

                    modified = true

                    // We simply don't append the instruction to the new program builder.

                    // Optionally, one could append a Nop instruction:

                    // b.append(Instruction.NOP)

                } else {

                    // Otherwise, keep the instruction.

                    b.append(instr)

                }

            }



            // If we didn't actually remove any gczeal instructions, this mutation attempt failed.

            guard modified else { return nil }



            // Optional: Add definition for 'b' if it's likely used undeclared in a debugger handler.

            // This is heuristic. A more robust approach would involve static analysis.

            // For simplicity matching the target negative case, we can add it if gczeal was removed.

             if program.code.contains(where: { $0.op is LoadBuiltin && ($0.op as! LoadBuiltin).builtinName == "Debugger" }) {

                 // Check if 'b' is already defined in the global scope or initial context.

                 // This check is simplified; a full check would need scope analysis.

                 let definesB = program.code.contains { instr in

                     (instr.op is DeclareVariable && instr.stringEncoding.contains("b")) ||

                     (instr.op is Assign && instr.output.identifier == "b") // Basic check

                 }

                 if !definesB {

                     let initialValue = b.loadString("defined") // Or load undefined, null, etc.

                     b.declareVariable("b", initialValue: initialValue)

                     // Note: This prepends the definition. Ideally, it should be placed

                     // before the first potential use, but global scope start is often safe.

                 }

             }





            // Optional: Add a triggering evaluate call at the end, similar to the negative example.

            // This helps ensure some code runs after the modification.

             if let eval = b.loadBuiltin("evaluate") {

                if let globalScope = b.loadBuiltin("globalThis") { // Assuming 'a' might be attached to globalThis or similar context

                     // Try to find 'a' or use a generic trigger

                     let targetVar = b.findVariable(named: "a") ?? globalScope

                     if let codeToEval = b.loadString("1+1") { // Simple code unlikely to crash

                         b.callMethod("eval", on: targetVar, withArgs: [codeToEval])

                     } else if let codeToEval = b.loadString("void 0;") { // Even simpler

                         b.callFunction(eval, withArgs: [codeToEval])

                     }

                 } else {

                      if let codeToEval = b.loadString("1+1") { // Simple code unlikely to crash

                           b.callFunction(eval, withArgs: [codeToEval])

                       }

                 }

             }



        } // End of b.adopting block



        // Return the modified program

        return b.finalize()

    }

}
