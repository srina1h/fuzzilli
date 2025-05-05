

// Mutator specific to the SpiderMonkey Debugger.createSource crash (Issue # from bug report if available).

// This mutator identifies the specific crashing pattern involving `o2.discardSource = true`

// followed by a `Debugger().addDebuggee(v3).createSource(true)` chain and transforms it

// into a non-crashing variant by removing the `discardSource` setting and replacing

// the `createSource` call with an alternative sequence that involves evaling a function

// and accessing its source text via `getOwnPropertyDescriptor`.

//

// Transforms Code Like:

//   const o2 = { "newCompartment": true };

//   o2.discardSource = true;                             // Target Line 1 (to remove)

//   const v3 = newGlobal(o2);

//   const v5 = Debugger();

//   const v6 = v5.addDebuggee(v3);

//   v6.createSource(true);                               // Target Line 2 (to replace)

//   gc();

//

// Into Code Like:

//   const o2 = { "newCompartment": true };

//   // o2.discardSource = true; // Removed

//   const v3 = newGlobal(o2);

//   const v5 = Debugger();                               // Kept (or re-emitted)

//   const v6 = v5.addDebuggee(v3);                       // Kept (or re-emitted)

//   // Ensure some script exists in the debuggee

//   v3.eval("function f() { return 1; }");               // Added Section

//   // Call getOwnPropertyDescriptor instead of createSource

//   const v7 = v6.getOwnPropertyDescriptor("f");

//   const v8 = v7.value;

//   const v9 = v8.script;

//   const v10 = v9.source;

//   const v11 = v10.text;                               // End Added Section

//   gc();                                                // Kept

//

public class SpiderMonkeyDebuggerCreateSourceMutator: Mutator {



    public init() {

        super.init(name: "SpiderMonkeyDebuggerCreateSourceMutator")

    }



    // This mutator operates on the entire program structure to reliably identify and replace the pattern.

    override public func mutate(_ program: Program, for fuzzer: Fuzzer, at index: Int?) -> Program? {

        let b = fuzzer.makeBuilder()

        // Adopt variables from the original program into the new builder's scope.

        b.adopting(from: program)



        var createSourceInstrIndex: Int? = nil

        var addDebuggeeInstrIndex: Int? = nil

        var debuggerCallInstrIndex: Int? = nil

        var discardSourceStoreInstrIndex: Int? = nil

        var newGlobalInstrIndex: Int? = nil



        // Variables involved in the pattern

        var optionsObjectVar: Variable? = nil       // The object passed to newGlobal (e.g., o2)

        var newGlobalResultVar: Variable? = nil     // The result of newGlobal (e.g., v3)

        var debuggerResultVar: Variable? = nil      // The result of Debugger()

        var addDebuggeeResultVar: Variable? = nil   // The result of addDebuggee()



        var foundPattern = false



        // --- Pass 1: Scan the program to find the instruction indices and variables of the pattern ---

        for i in 0..<program.size {

            let instr = program[i]



            // Tentatively identify the options object (simplistic: first CreateObject)

            // A more robust check might look for the object used in newGlobal.

            if optionsObjectVar == nil && instr.op is CreateObject {

                optionsObjectVar = instr.output

            }



            // Check for 'o2.discardSource = true'

            // Requires StoreProperty "discardSource" operating on the options object.

            // We also need to check if the value being stored is 'true'. This is approximated.

            if let op = instr.op as? StoreProperty,

               op.propertyName == "discardSource",

               instr.input(0) == optionsObjectVar {

                // Crude check for 'true': assumes the input var likely comes from LoadBoolean(true)

                // A more robust check would trace instr.input(1) back.

                if program.findInstruction(producing: instr.input(1))?.op is LoadBoolean {

                   discardSourceStoreInstrIndex = i

                }

            }

            // Check for 'newGlobal(o2)'

            else if let op = instr.op as? CallFunction,

                    op.functionName == "newGlobal",

                    instr.numInputs > 0,

                    instr.input(0) == optionsObjectVar {

                newGlobalInstrIndex = i

                newGlobalResultVar = instr.output

            }

            // Check for 'Debugger()'

            else if let op = instr.op as? CallFunction,

                    op.functionName == "Debugger" {

                debuggerCallInstrIndex = i

                debuggerResultVar = instr.output

            }

            // Check for 'dbg.addDebuggee(v3)'

            else if let op = instr.op as? CallMethod,

                    op.methodName == "addDebuggee" {

                // Check if inputs match the results of Debugger() and newGlobal()

                if instr.numInputs == 2,

                   instr.input(0) == debuggerResultVar,

                   instr.input(1) == newGlobalResultVar {

                    addDebuggeeInstrIndex = i

                    addDebuggeeResultVar = instr.output // Capture the output variable

                }

            }

            // Check for 'dbgGlobal.createSource(true)'

            else if let op = instr.op as? CallMethod,

                    op.methodName == "createSource" {

                // Check if input matches the result of addDebuggee()

                if instr.numInputs >= 1, // Allows for potential optional arguments

                   instr.input(0) == addDebuggeeResultVar {

                    // Check if the argument is likely 'true'

                    if instr.numInputs >= 2,

                       program.findInstruction(producing: instr.input(1))?.op is LoadBoolean {

                        createSourceInstrIndex = i



                        // --- Pattern Confirmation ---

                        // Check if all parts were found and are roughly in order

                        if let dsIdx = discardSourceStoreInstrIndex,

                           let ngIdx = newGlobalInstrIndex,

                           let dbgIdx = debuggerCallInstrIndex,

                           let addDbgIdx = addDebuggeeInstrIndex,

                           // Basic order check: newGlobal and Debugger happen before addDebuggee,

                           // which happens before createSource. discardSource can be flexible but usually near newGlobal.

                           ngIdx < addDbgIdx, dbgIdx < addDbgIdx, addDbgIdx < i {

                            foundPattern = true

                            // Stop scanning once the full pattern ending in createSource is found

                            break

                        }

                    }

                }

            }

        }



        // --- Guard: Ensure the full pattern was found ---

        guard foundPattern,

              let discardSourceIdx = discardSourceStoreInstrIndex,

              let createSourceIdx = createSourceInstrIndex,

              let globalVar = newGlobalResultVar,       // The debuggee global object

              let dbgGlobalVar = addDebuggeeResultVar   // The Debugger.Global object

        else {

            // The specific pattern required for this mutator was not found.

            return nil

        }



        // --- Pass 2: Rebuild the program with modifications ---

        var mutationOccurred = false

        for i in 0..<program.size {

            let currentInstr = program[i]



            if i == discardSourceIdx {

                // Action: Skip the 'o2.discardSource = true' instruction entirely.

                mutationOccurred = true

                continue // Do not append this instruction to the new program builder 'b'.

            } else if i == createSourceIdx {

                // Action: Replace the 'createSource' call with the alternative sequence.

                mutationOccurred = true



                // Get the handles to the necessary variables within the builder's context.

                // `b.adopt()` ensures we are using the correct variable reference after adoption.

                let currentGlobalVar = b.adopt(globalVar)

                let currentDbgGlobalVar = b.adopt(dbgGlobalVar)



                // --- Insert the replacement code sequence ---

                // 1. v3.eval("function f() { return 1; }");

                let scriptCode = b.loadString("function f() { return 1; }")

                // The eval result is not used, so no output variable is needed.

                b.callMethod(currentGlobalVar, methodName: "eval", args: [scriptCode])



                // 2. dbgGlobal.getOwnPropertyDescriptor("f").value.script.source.text;

                let propName = b.loadString("f")

                let descriptor = b.callMethod(currentDbgGlobalVar, methodName: "getOwnPropertyDescriptor", args: [propName])

                let value = b.loadProperty(descriptor, "value")

                let script = b.loadProperty(value, "script")

                let source = b.loadProperty(script, "source")

                // Access the 'text' property. The result is implicitly discarded as it's not assigned.

                b.loadProperty(source, "text")

                // --- End of replacement sequence ---



                // Skip the original 'createSource' instruction itself.

                continue // Do not append the original createSource instruction.

            } else {

                // Action: Keep all other instructions.

                // Adopt the instruction and its variables into the builder's context and append it.

                b.adopt(currentInstr) {

                    // If the instruction being adopted is the one that produced dbgGlobalVar,

                    // ensure it *does* have an output assigned in the builder, as we rely on it later.

                    // `b.adopt` should handle maintaining the output variable association correctly.

                    b.append($0)

                }

            }

        }



        // Return the modified program if a mutation was successfully applied.

        return mutationOccurred ? b.finalize() : nil

    }

}
