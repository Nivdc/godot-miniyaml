# SGYP
SGYP - Simple GDScript YAML Parser.

A single-file YAML parser written in GDScript.

## Implementation Introduction
Simply put, the role of a YAML parser is to convert a character stream that conforms to the YAML specification into an object that can be used by the program.

So, how can we do this?
The answer may be surprisingly simple: read the character stream, just like a human would, block by block, line by line, word by word, character by character.

The **recognizable format** (defined by the specification) in the character stream is then extracted and placed into the **Object** provided by the GDScript.

Once you understand this, the only thing left is to fight the specification......😭