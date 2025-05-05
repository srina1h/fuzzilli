

// Specific mutator to transform the crashing Temporal/Prototype chain example

// into the non-crashing version by applying targeted fixes.

// This is more akin to a targeted reducer than a general-purpose mutator.

public class FixTemporalPrototypeCrashMutator: Mutator {



    public init() {

        super.init(name: "FixTemporalPrototypeCrashMutator")

    }



    public override func mutate(_ program: Program, for fuzzer: Fuzzer) -> Program? {

        let b = fuzzer.makeBuilder()

        b.adopting(from: program) {

            // Flags to track if we've applied the specific fixes

            var removedSelfAssignment = false

            var replacedYearCallArg = false

            var removedProtoChainMod = false



            var calendarVar: Variable? = nil // Track the variable holding the Calendar object (v11)

            var calendarVarProto: Variable? = nil // Track v3 = v1.entries().__proto__

            var classInstanceVar: Variable? = nil // Track v5 = new C4()



            // First pass to identify key variables (simplistic identification based on the example)

            for instr in program.code {

                if instr.op is CreateObject { // Assuming 'new C4()' corresponds to CreateObject or similar

                    // Heuristic: The last CreateObject might be v5

                    classInstanceVar = instr.output

                }

                if instr.op is CallMethod && (instr.op as! CallMethod).methodName == "getCalendar" {

                     // Heuristic: The output of getCalendar is likely v11

                    calendarVar = instr.output

                }

                 if instr.op is GetProperty && (instr.op as! GetProperty).propertyName == "__proto__" && instr.numInputs > 0 {

                     // Heuristic: If the input comes from .entries(), it might be v3

                     // This is brittle - a better approach would involve type analysis or tracing variable origins

                     let inputInstrIndex = program.code.findInstruction(producing: instr.input(0))

                     if let inputInstrIndex = inputInstrIndex, program.code[inputInstrIndex].op is CallMethod && (program.code[inputInstrIndex].op as! CallMethod).methodName == "entries" {

                         calendarVarProto = instr.output // This is actually v3 in the example

                     }

                 }

            }



            // Second pass: Apply transformations

            var i = 0

            while i < b.currentCode.count {

                var instruction = b.currentCode[i]

                var removedCurrent = false



                // 1. Remove v11.calendar = v11;

                if let calVar = calendarVar,

                   let op = instruction.op as? SetProperty,

                   op.propertyName == "calendar",

                   instruction.numInputs == 2,

                   instruction.input(0) == calVar,

                   instruction.input(1) == calVar {

                    b.remove(at: i)

                    removedSelfAssignment = true

                    removedCurrent = true

                }

                // 2. Fix v11.year(v11) call

                else if let calVar = calendarVar,

                        let op = instruction.op as? CallMethod,

                        op.methodName == "year",

                        instruction.numInputs > 0,

                        instruction.input(0) == calVar, // Calling .year on the calendar object

                        instruction.numArguments == 1,

                        instruction.input(1) == calVar // Passing the calendar object itself as argument

                {

                    // Insert code to create a valid date argument before the call

                    let thisVar = b.loadBuiltin("this")

                    let temporalVar = b.getProperty(of: thisVar, withName: "Temporal")

                    let nowVar = b.getProperty(of: temporalVar, withName: "Now")

                    let plainDateIsoFunc = b.getProperty(of: nowVar, withName: "plainDateISO")

                    let dateArg = b.callFunction(plainDateIsoFunc, withArgs: [])



                    // Replace the argument in the original call

                    var inouts = instruction.inouts

                    inouts[1] = dateArg // Replace the argument v11 with dateArg

                    let newInstr = Instruction(instruction.op, inouts: inouts)

                    b.replace(at: i, with: newInstr)

                    replacedYearCallArg = true

                }

                // 3. Remove prototype chain modification

                //    Look for t9 = v3.__proto__; t9.__proto__ = v5;

                //    Where v3 is approximated by calendarVarProto and v5 by classInstanceVar

                else if let protoVar = calendarVarProto, // Check if we identified v3

                        let op = instruction.op as? GetProperty,

                        op.propertyName == "__proto__",

                        instruction.numInputs == 1,

                        instruction.input(0) == protoVar

                {

                     let t9 = instruction.output // Potential candidate for t9

                     // Look ahead for the SetProperty instruction

                     if i + 1 < b.currentCode.count {

                        let nextInstr = b.currentCode[i+1]

                        if let classInstVar = classInstanceVar, // Check if we identified v5

                           let nextOp = nextInstr.op as? SetProperty,

                           nextOp.propertyName == "__proto__",

                           nextInstr.numInputs == 2,

                           nextInstr.input(0) == t9,

                           nextInstr.input(1) == classInstVar {

                               // Found the sequence, remove both instructions

                               b.remove(at: i+1) // Remove SetProperty first (higher index)

                               b.remove(at: i)   // Remove GetProperty

                               removedProtoChainMod = true

                               removedCurrent = true

                               // Skip incrementing 'i' because we removed the current instruction

                        }

                     }

                }



                if !removedCurrent {

                    i += 1

                }

            }



            // Only return the mutated program if all intended transformations were applied

            if removedSelfAssignment && replacedYearCallArg && removedProtoChainMod {

                return b.finalize()

            } else {

                // If the specific patterns weren't found or applied, discard the mutation

                return nil

            }

        }

    }

}
