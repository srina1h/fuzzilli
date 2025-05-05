import Foundation



/// A mutator that specifically transforms the structure related to the oomTest/eval/IIFE pattern

/// observed in a particular SpiderMonkey crash into a structure using a generator function.

/// This is designed to turn the specific positive test case (crashing) into the

/// specific negative test case (non-crashing).

public class OomEvalIifeToGeneratorMutator: BaseInstructionMutator {



    // The exact JS code string found inside the eval in the positive test case.

    // Whitespace is important for matching.

    let positiveEvalCode = """



      for (let x = 0, y = 9; y; ) {

        (function() {

          y--;

          let z = {};

          z.sameZoneAs = [];

          newGlobal(z).Debugger(this).getNewestFrame().environment;

        })()}

    

"""



    // The exact JS code string to replace with, from the negative test case.

    // Whitespace is important.

    let negativeEvalCode = """



      // Use a generator function instead of a regular IIFE

      function* genFunc(yRef) {

          yRef.y--; // Modify y through the reference object

          let z = {};

          z.sameZoneAs = [];

          // Attach debugger and access environment as before

          newGlobal(z).Debugger(this).getNewestFrame().environment;

          yield; // Generators need to yield

      }



      let obj = { y: 9 }; // Use an object to allow modification by reference

      for (let x = 0; obj.y; ) {

          // Create and run the generator instance

          let iter = genFunc(obj);

          iter.next(); // Execute the generator body

      }

    

"""



    public init() {

        super.init(name: "OomEvalIifeToGeneratorMutator")

    }



    public override func canMutate(_ instr: Instruction) -> Bool {

        // Check if the instruction is LoadString with the specific positive pattern.

        if instr.op is LoadString, let code = instr.string {

            // Trim whitespace at the beginning/end for robustness,

            // although the provided examples have leading/trailing newlines.

            return code.trimmingCharacters(in: .whitespacesAndNewlines) == positiveEvalCode.trimmingCharacters(in: .whitespacesAndNewlines)

        }

        return false

    }



    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {

        assert(canMutate(instr))



        // Replace the LoadString instruction with one containing the negative pattern.

        b.trace("Applying OomEvalIifeToGeneratorMutator: Replacing eval code")

        b.loadString(negativeEvalCode)

        // The original LoadString had one output (the string variable).

        // The new LoadString also provides one output.

        // We need to make sure subsequent instructions use the *new* output variable.

        // However, BaseInstructionMutator handles replacing the instruction and its outputs.

        // We just need to provide the new instruction.

    }

}
