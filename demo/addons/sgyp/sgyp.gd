extends Node
# class_name SGYP extends RefCounted
# # You can replace the above comment and use SGYP like a normal class, 
# # but the plugin form allows you to decide whether to enable SGYP.

static func parse(yaml_data) -> Variant:
    var yaml_data_type :String = type_string(typeof(yaml_data))
    if yaml_data_type == "String":
        return Parser.new().load(yaml_data.to_utf8_buffer())
    elif yaml_data_type == "PackedByteArray":
        return Parser.new().load(yaml_data)
    elif yaml_data_type == "StreamPeerBuffer":
        return Parser.new().load(yaml_data.data_array)
    else:
        Parser.error("Unsupported YAML data type.")
        return null


class Parser:

    func load(yaml_bytes:PackedByteArray) -> Variant:
        var trees = _build_serialization_tree(yaml_bytes) # stage 1:Parsing the Presentation Stream
        return null

    func _build_serialization_tree(yaml_bytes :PackedByteArray):
        var yaml_string = match_bom_return_string(yaml_bytes)
        var tokens = Scanner.new(yaml_string).tokenize()
        for t in tokens:
            print(t.type)

    class Token:
        # Scanner produces tokens of the following types:
        # STREAM-START
        # STREAM-END
        # DIRECTIVE(name, value)
        # DOCUMENT-START
        # DOCUMENT-END
        # BLOCK-SEQUENCE-START
        # BLOCK-MAPPING-START
        # BLOCK-END
        # FLOW-SEQUENCE-START
        # FLOW-MAPPING-START
        # FLOW-SEQUENCE-END
        # FLOW-MAPPING-END
        # BLOCK-ENTRY
        # FLOW-ENTRY
        # KEY
        # VALUE
        # ALIAS(value)
        # ANCHOR(value)
        # TAG(value)
        # SCALAR(value, plain, style)
        static var valid_types := [
            "STREAM_START","STREAM_END",
            "DIRECTIVE",
            "DOCUMENT_START", "DOCUMENT_END",
            "BLOCK_SEQUENCE_START", "BLOCK_MAPPING_START", "BLOCK_END",
            "FLOW_SEQUENCE_START", "FLOW_MAPPING_START", "FLOW_SEQUENCE_END", "FLOW_MAPPING_END",
            "BLOCK_ENTRY", "FLOW_ENTRY",
            "KEY", "VALUE", "ALIAS", "ANCHOR", "TAG", "SCALAR"
            ]
        var type:String
        var raw_text:String

        func _init(p_type:String, ...args) -> void:
            assert(p_type in valid_types, "Token type must be one of the valid_types.")
            type = p_type
            # raw_text = p_raw_text

    static func soft_assert(condition: bool, message: String = "Soft assertion failed."):
        if not condition: push_error("SGYP Error: " + message)

    static func error(message: String = "Something is wrong."):
        soft_assert(false, message)

    static func warn(message: String = "Something is wrong."):
        push_warning("SGYP Warning: " + message)

    static func match_bom_return_string(yaml_bytes:PackedByteArray) -> String:
        var character_encoding = capture_byte_order_mark(yaml_bytes)
        var yaml_string :String
        match character_encoding:
            "UTF-8"               : yaml_string = yaml_bytes.get_string_from_utf8()
            "UTF-16LE", "UTF-16BE": yaml_string = yaml_bytes.get_string_from_utf16()
            "UTF-32LE", "UTF-32BE": yaml_string = yaml_bytes.get_string_from_utf32()
        # Remove the BOM, if there is one
        return yaml_string if not yaml_string.begins_with("\uFEFF") else yaml_string.erase(0, 1)

    static func capture_byte_order_mark(bytes :PackedByteArray) -> String:
        # NOTE: I don't know why, but match doesn't work for PackedByteArray.
        var first_char := Array(bytes.slice(0, 4))
        match first_char:
            # Explicit BOM
            [239, 187, 191, _  ] : return "UTF-8"
            [255, 254, 0,   0  ] : return "UTF-32LE"
            [255, 254, _,   _  ] : return "UTF-16LE"
            [0,   0,   254, 255] : return "UTF-32BE"
            [254, 255, _,   _  ] : return "UTF-16BE"
            # ASCII first character
            [_,   0,   0,   0  ] : return "UTF-32LE"
            [_,   0,   _,   _  ] : return "UTF-16LE"
            [0,   0,   0,   _  ] : return "UTF-32BE"
            [0,   _,   _,   _  ] : return "UTF-16BE"
            # Default
            _                    : return "UTF-8"



    # static func remove_indent(line, indent_level):
    #     return line.trim_prefix(" ".repeat(indent_level*2)) if indent_level != 0 else line



    class Scanner:
        # The Scanner behaves very similarly to PyYAML's Scanner and Reader, 
        # but SGYP doesn't need to handle streaming data, 
        # so it outputs the results (i.e tokens) to the Parser all at once.

        # and '\x85\u2028\u2029' is not supported.

        # If you want to learn more details, you can view the PyYAML source code.
        # Scanner: https://github.com/yaml/pyyaml/blob/main/lib/yaml/scanner.py
        # Reader : https://github.com/yaml/pyyaml/blob/main/lib/yaml/reader.py

        var yaml_string  := ""
        var char_index   := 0 # = Reader.pointer
        var line_index   := 0 # = Reader.line
        var column_index := 0 # = Reader.column

        func peek(index = 0): # peek the next i-th character
            return yaml_string[char_index + index]

        func prefix(length = 1): # peek the next l characters
            return yaml_string.substr(char_index, length)
        
        func forward(length = 1): # read the next l characters and move the pointer.
            while length > 0:
                var ch = yaml_string[char_index]
                char_index += 1
                # In SGYP, we use only one type of newline character '\n', and we convert other types of newline characters to this one.
                if ch == '\n':
                    line_index += 1
                    column_index = 0
                elif ch != '\uFEFF':
                    column_index += 1
                length -= 1

        # Had we reached the end of the stream?
        var done := false

        # The number of unclosed '{' and '['. `flow_level == 0` means block
        # context.
        var flow_level = 0

        var tokens = []

        # # Number of tokens that were emitted through the `get_token` method.
        # var tokens_taken = 0

        # The current indentation level.
        var indent = -1

        # Past indentation levels.
        var indents = []

        # Variables related to simple keys treatment.

        # A simple key is a key that is not denoted by the '?' indicator.
        # Example of simple keys:
        #   ---
        #   block simple key: value
        #   ? not a simple key:
        #   : { flow simple key: value }
        # We emit the KEY token before all keys, so when we find a potential
        # simple key, we try to locate the corresponding ':' indicator.
        # Simple keys should be limited to a single line and 1024 characters.

        # Can a simple key start at the current position? A simple key may
        # start:
        # - at the beginning of the line, not counting indentation spaces
        #       (in block context),
        # - after '{', '[', ',' (in the flow context),
        # - after '?', ':', '-' (in the block context).
        # In the block context, this flag also signifies if a block collection
        # may start at the current position.
        var allow_simple_key = true

        # Keep track of possible simple keys. This is a dictionary. The key
        # is `flow_level`; there can be no more that one possible simple key
        # for each level. The value is a SimpleKey record:
        #   (token_number, required, index, line, column, mark)
        # A simple key may start with ALIAS, ANCHOR, TAG, SCALAR(flow),
        # '[', or '{' tokens.
        var possible_simple_keys = {}
        var need_more_tokens :bool:
            get:
                return not done

        # 5.4. Line Break Characters
        static var line_breaks = ["\r\n", "\r", "\n"]

        # 5.5. White Space Characters
        static var white_space = [" ", "\t"]
        
        # 6.2. Separation Spaces
        static var separate_in_line = white_space # [66] s-separate-in-line

        # 6.6. Comments
        static var non_content = line_breaks
        static var comment_ends = non_content # [76] b-comment


        func _init(p_yaml_string:String) -> void:
            fetch_stream_start()
            yaml_string = p_yaml_string

        static func convert_line_breaks_to_only_line_break(text :String, only_line_break :String) -> String:
            # The key here is that we have to treat line_breaks as the same symbol
            # So first, We choose a single character line_break as the only_line_break( '\n' )
            # Then convert all line_breaks that are not only_line_break to only_line_break
            assert(line_breaks.has(only_line_break), "only_line_break should be one of line_breaks.")
            for line_break in line_breaks:
                if line_break != only_line_break:
                    text = only_line_break.join(text.split(line_break))
            return text

        func tokenize():
            yaml_string = convert_line_breaks_to_only_line_break(yaml_string, '\n')
            yaml_string += "\u0003" # Adding an EOF makes the code simpler.

            while need_more_tokens:
                fetch_more_tokens()
            return tokens

        func fetch_more_tokens():
            # Eat whitespaces and comments until we reach the next token.
            scan_to_next_token()

            # Remove obsolete possible simple keys.
            stale_possible_simple_keys()
            # Compare the current indentation and column. It may add some tokens
            # and decrease the current indentation level.
            unwind_indent(column_index)

            var ch = peek()

            # Is it the end of stream?
            if ch == '\u0003':
                return fetch_stream_end()

            # Is it a directive?
            if ch == '%' and check_directive():
                return fetch_directive()

            # Is it the document start?
            if ch == '-' and check_document_start():
                return fetch_document_start()

            # Is it the document end?
            if ch == '.' and check_document_end():
                return fetch_document_end()

            # TODO: support for BOM within a stream.
            #if ch == '\uFEFF':
            #    return fetch_bom()    <-- issue BOMToken

            # Note: the order of the following checks is NOT significant.

            # Is it the flow sequence start indicator?
            if ch == '[':
                return fetch_flow_sequence_start()

            # Is it the flow mapping start indicator?
            if ch == '{':
                return fetch_flow_mapping_start()

            # Is it the flow sequence end indicator?
            if ch == ']':
                return fetch_flow_sequence_end()

            # Is it the flow mapping end indicator?
            if ch == '}':
                return fetch_flow_mapping_end()

            # Is it the flow entry indicator?
            if ch == ',':
                return fetch_flow_entry()

            # Is it the block entry indicator?
            if ch == '-' and check_block_entry():
                return fetch_block_entry()

            # Is it the key indicator?
            if ch == '?' and check_key():
                return fetch_key()

            # Is it the value indicator?
            if ch == ':' and check_value():
                return fetch_value()

            # Is it an alias?
            if ch == '*':
                return fetch_alias()

            # Is it an anchor?
            if ch == '&':
                return fetch_anchor()

            # Is it a tag?
            if ch == '!':
                return fetch_tag()

            # Is it a literal scalar?
            if ch == '|' and flow_level == 0:
                return fetch_literal()

            # Is it a folded scalar?
            if ch == '>' and flow_level == 0:
                return fetch_folded()

            # Is it a single quoted scalar?
            if ch == '\'':
                return fetch_single()

            # Is it a double quoted scalar?
            if ch == '\"':
                return fetch_double()

            # It must be a plain scalar then.
            if check_plain():
                return fetch_plain()

            # No? It's an error. Let's produce a nice error message.
            Parser.error("while scanning for the next token found character %c that cannot start any token." % ch)




        # Simple keys treatment.

        # func next_possible_simple_key():
        #     # Return the number of the nearest possible simple key. Actually we
        #     # don't need to loop through the whole dictionary. We may replace it
        #     # with the following code:
        #     #   if not possible_simple_keys:
        #     #       return None
        #     #   return possible_simple_keys[
        #     #           min(possible_simple_keys.keys())].token_number
        #     min_token_number = None
        #     for level in possible_simple_keys:
        #         key = possible_simple_keys[level]
        #         if min_token_number is None or key.token_number < min_token_number:
        #             min_token_number = key.token_number
        #     return min_token_number

        func stale_possible_simple_keys():
            # Remove entries that are no longer possible simple keys. According to
            # the YAML specification, simple keys
            # - should be limited to a single line,
            # - should be no longer than 1024 characters.
            # Disabling this procedure will allow simple keys of any length and
            # height (may cause problems if indentation is broken though).
            for level in possible_simple_keys.keys():
                var key = possible_simple_keys[level]
                if key.line_index != line_index  \
                        or char_index - key.char_index > 1024:
                    if key.required:
                        # Parser.warn("while scanning a simple key", key.mark,
                        #         "could not find expected ':'", get_mark())
                        Parser.error("while scanning a simple key could not find expected ':'.")
                    possible_simple_keys.erase(level)

        func save_possible_simple_key():
            # The next token may start a simple key. We check if it's possible
            # and save its position. This function is called for
            #   ALIAS, ANCHOR, TAG, SCALAR(flow), '[', and '{'.

            # Check if a simple key is required at the current position.
            var required = flow_level == 0 and indent == column_index

            # The next token might be a simple key. Let's save it's number and
            # position.
            if allow_simple_key:
                remove_possible_simple_key()
                var token_number = tokens.size()
                # key = SimpleKey(token_number, required,
                #         index, line, column, get_mark())
                var key = {
                    "token_number":token_number,
                    "required":required,
                    "line_index":line_index,
                }
                possible_simple_keys[flow_level] = key

        func remove_possible_simple_key():
            # Remove the saved possible key position at the current flow level.
            if flow_level in possible_simple_keys:
                var key = possible_simple_keys[flow_level]
                
                if key.required:
                        Parser.error("while scanning a simple key could not find expected ':'.")


                possible_simple_keys.erase(flow_level)

        # Indentation functions.

        func unwind_indent(column:int):
            ## In flow context, tokens should respect indentation.
            ## Actually the condition should be `indent >= column` according to
            ## the spec. But this condition will prohibit intuitively correct
            ## constructions such as
            ## key : {
            ## }
            #if flow_level and indent > column:
            #    raise ScannerError(None, None,
            #            "invalid indentation or unclosed '[' or '{'",
            #            get_mark())

            # In the flow context, indentation is ignored. We make the scanner less
            # restrictive then specification requires.
            if flow_level > 0:
                return

            # In block context, we may need to issue the BLOCK-END tokens.
            while indent > column:
                indent = indents.pop_back()
                tokens.append(Token.new("BLOCK_END"))

        func add_indent(column:int):
            # Check if we need to increase indentation.
            if indent < column:
                indents.append(indent)
                indent = column
                return true
            return false

        # Fetchers.

        func fetch_stream_start():
            # We always add STREAM-START as the first token and STREAM-END as the
            # last token.
            
            # Add STREAM-START.
            tokens.append(Token.new("STREAM_START"))


        func fetch_stream_end():

            # Set the current indentation to -1.
            unwind_indent(-1)

            # Reset simple keys.
            remove_possible_simple_key()
            allow_simple_key = false
            possible_simple_keys = {}
            
            # Add STREAM-END.
            tokens.append(Token.new("STREAM_END"))

            # The steam is finished.
            done = true

        func fetch_directive():
            
            # Set the current indentation to -1.
            unwind_indent(-1)

            # Reset simple keys.
            remove_possible_simple_key()
            allow_simple_key = false

            # Scan and add DIRECTIVE.
            tokens.append(scan_directive())

        func fetch_document_start():
            fetch_document_indicator("DOCUMENT_START")

        func fetch_document_end():
            fetch_document_indicator("DOCUMENT_END")

        func fetch_document_indicator(token_type:String):

            # Set the current indentation to -1.
            unwind_indent(-1)

            # Reset simple keys. Note that there could not be a block collection
            # after '---'.
            remove_possible_simple_key()
            allow_simple_key = false

            # Add DOCUMENT-START or DOCUMENT-END.
            forward(3)
            tokens.append(Token.new(token_type))

        func fetch_flow_sequence_start():
            fetch_flow_collection_start("FLOW_SEQUENCE_START")

        func fetch_flow_mapping_start():
            fetch_flow_collection_start("FLOW_MAPPING_START")

        func fetch_flow_collection_start(token_type:String):

            # '[' and '{' may start a simple key.
            save_possible_simple_key()

            # Increase the flow level.
            flow_level += 1

            # Simple keys are allowed after '[' and '{'.
            allow_simple_key = true

            # Add FLOW-SEQUENCE-START or FLOW-MAPPING-START.
            forward()
            tokens.append(Token.new(token_type))

        func fetch_flow_sequence_end():
            fetch_flow_collection_end("FLOW_SEQUENCE_END")

        func fetch_flow_mapping_end():
            fetch_flow_collection_end("FLOW_MAPPING_END")

        func fetch_flow_collection_end(token_type:String):

            # Reset possible simple key on the current level.
            remove_possible_simple_key()

            # Decrease the flow level.
            flow_level -= 1

            # No simple keys after ']' or '}'.
            allow_simple_key = false

            # Add FLOW-SEQUENCE-END or FLOW-MAPPING-END.
            forward()
            tokens.append(Token.new(token_type))

        func fetch_flow_entry():

            # Simple keys are allowed after ','.
            allow_simple_key = true

            # Reset possible simple key on the current level.
            remove_possible_simple_key()

            # Add FLOW-ENTRY.
            forward()
            tokens.append(Token.new("FLOW_ENTRY"))

        func fetch_block_entry():
            # Block context needs additional checks.
            if flow_level == 0:

                # Are we allowed to start a new entry?
                if not allow_simple_key:
                    Parser.error("sequence entries are not allowed on line %d." % line_index)

                # We may need to add BLOCK-SEQUENCE-START.
                if add_indent(column_index):
                    tokens.append(Token.new("BLOCK_SEQUENCE_START"))

            # It's an error for the block entry to occur in the flow context,
            # but we let the parser detect this.
            else:
                pass

            # Simple keys are allowed after '-'.
            allow_simple_key = true

            # Reset possible simple key on the current level.
            remove_possible_simple_key()
            # Add BLOCK-ENTRY.
            forward()
            tokens.append(Token.new("BLOCK_ENTRY"))

        func fetch_key():
            
            # Block context needs additional checks.
            if flow_level == 0:

                # Are we allowed to start a key (not necessary a simple)?
                if not allow_simple_key:
                    Parser.error("mapping keys are not allowed on line %d." % line_index)

                # We may need to add BLOCK-MAPPING-START.
                if add_indent(column_index):
                    tokens.append(Token.new("BLOCK_MAPPING_START"))

            # Simple keys are allowed after '?' in the block context.
            allow_simple_key = flow_level == 0

            # Reset possible simple key on the current level.
            remove_possible_simple_key()

            # Add KEY.
            forward()
            tokens.append(Token.new("KEY"))

        func fetch_value():

            # Do we determine a simple key?
            if flow_level in possible_simple_keys:

                # Add KEY.
                var key = possible_simple_keys[flow_level]
                possible_simple_keys.erase(flow_level)
                tokens.insert(key.token_number,
                        Token.new("KEY"))

                # If this key starts a new block mapping, we need to add
                # BLOCK-MAPPING-START.
                if flow_level == 0:
                    if add_indent(key.column):
                        tokens.insert(key.token_number,
                                Token.new("BLOCK_MAPPING_START"))

                # There cannot be two simple keys one after another.
                allow_simple_key = false

            # It must be a part of a complex key.
            else:
                
                # Block context needs additional checks.
                # (Do we really need them? They will be caught by the parser
                # anyway.)
                if flow_level == 0:

                    # We are allowed to start a complex value if and only if
                    # we can start a simple key.
                    if not allow_simple_key:
                        Parser.error("mapping values are not allowed on line %d." % line_index)

                # If this value starts a new block mapping, we need to add
                # BLOCK-MAPPING-START.  It will be detected as an error later by
                # the parser.
                if flow_level == 0:
                    if add_indent(column_index):
                        # tokens.append(BlockMappingStartToken(mark, mark))
                        tokens.append(Token.new("BLOCK_MAPPING_START"))


                # Simple keys are allowed after ':' in the block context.
                allow_simple_key = flow_level == 0

                # Reset possible simple key on the current level.
                remove_possible_simple_key()

            # Add VALUE.
            forward()
            tokens.append(Token.new("VALUE"))

        func fetch_alias():

            # ALIAS could be a simple key.
            save_possible_simple_key()

            # No simple keys after ALIAS.
            allow_simple_key = false

            # Scan and add ALIAS.
            tokens.append(scan_anchor("ALIAS"))

        func fetch_anchor():

            # ANCHOR could start a simple key.
            save_possible_simple_key()

            # No simple keys after ANCHOR.
            allow_simple_key = false

            # Scan and add ANCHOR.
            tokens.append(scan_anchor("ANCHOR"))

        func fetch_tag():

            # TAG could start a simple key.
            save_possible_simple_key()

            # No simple keys after TAG.
            allow_simple_key = false

            # Scan and add TAG.
            tokens.append(scan_tag())

        func fetch_literal():
            fetch_block_scalar('|')

        func fetch_folded():
            fetch_block_scalar('>')

        func fetch_block_scalar(style):

            # A simple key may follow a block scalar.
            allow_simple_key = true

            # Reset possible simple key on the current level.
            remove_possible_simple_key()

            # Scan and add SCALAR.
            tokens.append(scan_block_scalar(style))

        func fetch_single():
            fetch_flow_scalar('\'')

        func fetch_double():
            fetch_flow_scalar('"')

        func fetch_flow_scalar(style):

            # A flow scalar could be a simple key.
            save_possible_simple_key()

            # No simple keys after flow scalars.
            allow_simple_key = false

            # Scan and add SCALAR.
            tokens.append(scan_flow_scalar(style))

        func fetch_plain():

            # A plain scalar could be a simple key.
            save_possible_simple_key()

            # No simple keys after plain scalars. But note that `scan_plain` will
            # change this flag if the scan is finished at the beginning of the
            # line.
            allow_simple_key = false

            # Scan and add SCALAR. May change `allow_simple_key`.
            tokens.append(scan_plain())

        # Checkers.

        func check_directive():

            # DIRECTIVE:        ^ '%' ...
            # The '%' indicator is already checked.
            if column_index == 0:
                return true

        func check_document_start():

            # DOCUMENT-START:   ^ '---' (' '|'\n')
            if column_index == 0:
                if prefix(3) == '---'  \
                        and peek(3) in '\u0003 \t\r\n':
                    return true

        func check_document_end():

            # DOCUMENT-END:     ^ '...' (' '|'\n')
            if column_index == 0:
                if prefix(3) == '...'  \
                        and peek(3) in '\u0003 \t\r\n':
                    return true

        func check_block_entry():

            # BLOCK-ENTRY:      '-' (' '|'\n')
            return peek(1) in '\u0003 \t\r\n'

        func check_key():

            # KEY(flow context):    '?'
            if flow_level > 0:
                return true

            # KEY(block context):   '?' (' '|'\n')
            else:
                return peek(1) in '\u0003 \t\r\n'

        func check_value():

            # VALUE(flow context):  ':'
            if flow_level > 0:
                return true

            # VALUE(block context): ':' (' '|'\n')
            else:
                return peek(1) in '\u0003 \t\r\n'

        func check_plain():

            # A plain scalar may start with any non-space character except:
            #   '-', '?', ':', ',', '[', ']', '{', '}',
            #   '#', '&', '*', '!', '|', '>', '\'', '\"',
            #   '%', '@', '`'.
            #
            # It may also start with
            #   '-', '?', ':'
            # if it is followed by a non-space character.
            #
            # Note that we limit the last rule to the block context (except the
            # '-' character) because we want the flow context to be space
            # independent.
            var ch = peek()
            return ch not in '\u0003 \t\r\n-?:,[]{}#&*!|>\'\"%@`'  \
                    or (peek(1) not in '\u0003 \t\r\n'
                            and (ch == '-' or (flow_level == 0 and ch in '?:')))

        # Scanners.

        func scan_to_next_token():
            var found :=false
            while not found:
                while peek() in white_space:
                    forward()
                if peek() == '#':
                    while peek() != '\n':
                        forward()
                if scan_line_break():
                    if flow_level == 0:
                        allow_simple_key = true
                else:
                    found = true

        func scan_directive():
            # See the specification for details.
            forward()
            var name = scan_directive_name()
            var value = null
            if name == 'YAML':
                value = scan_yaml_directive_value()
            elif name == 'TAG':
                value = scan_tag_directive_value()
            else:
                while peek() not in '\u0003\r\n':
                    forward()
            scan_directive_ignored_line()
            return Token.new("DIRECTIVE", name, value)

        func scan_directive_name():
            # See the specification for details.
            var length = 0
            var ch = peek(length)
            while '0' <= ch <= '9' or 'A' <= ch <= 'Z' or 'a' <= ch <= 'z'  \
                    or ch in '-_':
                length += 1
                ch = peek(length)
            if not length:
                # raise ScannerError("while scanning a directive", start_mark,
                #         "expected alphabetic or numeric character, but found %r"
                #         % ch, get_mark())
                Parser.error("while scanning a directive expected alphabetic or numeric character, but found %c" % ch)
            var value = prefix(length)
            forward(length)
            ch = peek()
            if ch not in '\u0003 \r\n':
                # raise ScannerError("while scanning a directive", start_mark,
                #         "expected alphabetic or numeric character, but found %r"
                #         % ch, get_mark())
                Parser.error("while scanning a directive expected alphabetic or numeric character, but found %c" % ch)

            return value

        func scan_yaml_directive_value():
            # See the specification for details.
            while peek() in '\t ':
                forward()
            var major = scan_yaml_directive_number()
            if peek() != '.':
                Parser.error("while scanning YAML directive expected a digit or '.', but found %c" % peek())
            forward()
            var minor = scan_yaml_directive_number()
            if peek() not in '\u0003 \r\n':
                Parser.error("while scanning YAML directive expected a digit or ' ', but found %c" % peek())
            return [major, minor]

        func scan_yaml_directive_number():
            # See the specification for details.
            var ch = peek()
            if not ('0' <= ch <= '9'):
                Parser.error("while scanning YAML directive expected a digit, but found %c" % peek())
            var length = 0
            while '0' <= peek(length) <= '9':
                length += 1
            var value = int(prefix(length))
            forward(length)
            return value

        func scan_tag_directive_value():
            # See the specification for details.
            while peek() == ' ':
                forward()
            var handle = scan_tag_directive_handle()
            while peek() == ' ':
                forward()
            var prefix = scan_tag_directive_prefix()
            return [handle, prefix]

        func scan_tag_directive_handle():
            # See the specification for details.
            var value = scan_tag_handle('directive')
            var ch = peek()
            if ch != ' ':
                Parser.error("while scanning TAG directive expected ' ', but found %c" % peek())
            return value

        func scan_tag_directive_prefix():
            # See the specification for details.
            var value = scan_tag_uri('directive')
            var ch = peek()
            if ch not in '\u0003 \r\n':
                Parser.error("while scanning TAG directive expected ' ', but found %c" % peek())
            return value

        func scan_directive_ignored_line():
            # See the specification for details.
            while peek() == ' ':
                forward()
            if peek() == '#':
                while peek() not in '\u0003\r\n':
                    forward()
            var ch = peek()
            if ch not in '\u0003\r\n':
                Parser.error("while scanning TAG directive expected a comment or a line break, but found %c" % peek())
            scan_line_break()

        func scan_anchor(token_type:String):
            # The specification does not restrict characters for anchors and
            # aliases. This may lead to problems, for instance, the document:
            #   [ *alias, value ]
            # can be interpreted in two ways, as
            #   [ "value" ]
            # and
            #   [ *alias , "value" ]
            # Therefore we restrict aliases to numbers and ASCII letters.
            var indicator = peek()
            var name = 'alias' if indicator == '*' else 'anchor'
            forward()
            var length = 0
            var ch = peek(length)
            while '0' <= ch <= '9' or 'A' <= ch <= 'Z' or 'a' <= ch <= 'z'  \
                    or ch in '-_':
                length += 1
                ch = peek(length)
            if length == 0:
                Parser.error("while scanning an %s expected alphabetic or numeric character, but found %c"
                        % [name, ch])
            var value = prefix(length)
            forward(length)
            ch = peek()
            if ch not in '\u0003 \t\r\n?:,]}%@`':
                Parser.error("while scanning an %s expected alphabetic or numeric character, but found %c"
                        % [name, ch])
            return Token.new(token_type, value)

        func scan_tag():
            # See the specification for details.
            var ch = peek(1)
            var suffix
            var handle

            if ch == '<':
                handle = null
                forward(2)
                suffix = scan_tag_uri('tag')
                if peek() != '>':
                    Parser.error("while parsing a tag expected '>', but found %c" % peek())
                forward()
            elif ch in '\u0003 \t\r\n':
                handle = null
                suffix = '!'
                forward()
            else:
                var length = 1
                var use_handle = false
                while ch not in '\u0003 \r\n':
                    if ch == '!':
                        use_handle = true
                        break
                    length += 1
                    ch = peek(length)
                    
                handle = '!'
                if use_handle:
                    handle = scan_tag_handle('tag')
                else:
                    handle = '!'
                    forward()
                suffix = scan_tag_uri('tag')
            ch = peek()
            if ch not in '\u0003 \r\n':
                Parser.error("while scanning a tag expected ' ', but found %c" % ch)
            var value = [handle, suffix]
            return Token.new("TAG", value)

        func scan_block_scalar(style):
            # See the specification for details.

            var folded = true if style == '>' else false

            var chunks = []

            # Scan the header.
            forward()
            var temp_dic  = scan_block_scalar_indicators()
            var chomping  = temp_dic.chomping
            var increment = temp_dic.increment
            scan_block_scalar_ignored_line()

            # Determine the indentation level and go to the first non-empty line.
            var min_indent = indent+1
            var breaks
            var indent

            if min_indent < 1:
                min_indent = 1
            if increment == null:
                temp_dic = scan_block_scalar_indentation()
                breaks = temp_dic.breaks
                var max_indent = breaks.max_indent
                indent = max(min_indent, max_indent)
            else:
                indent = min_indent+increment-1
                breaks = scan_block_scalar_breaks(indent)
            var line_break = ''

            # Scan the inner part of the block scalar.
            var leading_non_space
            while column_index == indent and peek() != '\u0003':
                chunks.extend(breaks)
                leading_non_space = peek() not in ' \t'
                var length = 0
                while peek(length) not in '\u0003\r\n':
                    length += 1
                chunks.append(prefix(length))
                forward(length)
                line_break = scan_line_break()
                breaks = scan_block_scalar_breaks(indent)
                if column_index == indent and peek() != '\u0003':

                    # Unfortunately, folding rules are ambiguous.
                    #
                    # This is the folding according to the specification:
                    
                    if folded and line_break == '\n'    \
                            and leading_non_space and peek() not in ' \t':
                        if not breaks:
                            chunks.append(' ')
                    else:
                        chunks.append(line_break)
                    
                    # This is Clark Evans's interpretation (also in the spec
                    # examples):
                    #
                    #if folded and line_break == '\n':
                    #    if not breaks:
                    #        if peek() not in ' \t':
                    #            chunks.append(' ')
                    #        else:
                    #            chunks.append(line_break)
                    #else:
                    #    chunks.append(line_break)
                else:
                    break

            # Chomp the tail.
            if chomping != false: # chomping == null or chomping == true
                chunks.append(line_break)
            if chomping == true:
                chunks.extend(breaks)

            # We are done.
            # return ScalarToken(''.join(chunks), false, start_mark, end_mark,
            #         style)
            return Token.new("SCALAR", ''.join(chunks), false, style)

        func scan_block_scalar_indicators():
            # See the specification for details.
            var chomping = null
            var increment = null
            var ch = peek()
            if ch in '+-':
                if ch == '+':
                    chomping = true
                else:
                    chomping = false
                forward()
                ch = peek()
                if ch in '0123456789':
                    increment = int(ch)
                    if increment == 0:
                        Parser.error("while scanning a block scalar expected indentation indicator in the range 1-9, but found 0")
                    forward()
            elif ch in '0123456789':
                increment = int(ch)
                if increment == 0:
                    Parser.error("while scanning a block scalar expected indentation indicator in the range 1-9, but found 0")
                forward()
                ch = peek()
                if ch in '+-':
                    if ch == '+':
                        chomping = true
                    else:
                        chomping = false
                    forward()
            ch = peek()
            if ch not in '\u0003 \r\n':
                Parser.error("while scanning a block scalar expected chomping or indentation indicators, but found %c"% ch)
            return {"chomping":chomping, "increment":increment}

        func scan_block_scalar_ignored_line():
            # See the specification for details.
            while peek() == ' ':
                forward()
            if peek() == '#':
                while peek() not in '\u0003\r\n':
                    forward()
            var ch = peek()
            if ch not in '\u0003\r\n':
                Parser.error("while scanning a block scalar expected a comment or a line break, but found %c" % ch)
            scan_line_break()

        func scan_block_scalar_indentation():
            # See the specification for details.
            var chunks = []
            var max_indent = 0
            while peek() in ' \r\n':
                if peek() != ' ':
                    chunks.append(scan_line_break())
                else:
                    forward()
                    if column_index > max_indent:
                        max_indent = column_index
            return {"chunks":chunks, "max_indent":max_indent}

        func scan_block_scalar_breaks(indent):
            # See the specification for details.
            var chunks = []
            while column_index < indent and peek() == ' ':
                forward()
            while peek() in '\r\n':
                chunks.append(scan_line_break())
                while column_index < indent and peek() == ' ':
                    forward()
            return chunks

        func scan_flow_scalar(style):
            # See the specification for details.
            # Note that we loose indentation rules for quoted scalars. Quoted
            # scalars don't need to adhere indentation because " and ' clearly
            # mark the beginning and the end of them. Therefore we are less
            # restrictive then the specification requires. We only need to check
            # that document separators are not included in scalars.
            var double = true if style == '"' else false
            var chunks = []
            # var start_mark = get_mark()
            var quote = peek()
            forward()
            chunks.extend(scan_flow_scalar_non_spaces(double))
            while peek() != quote:
                chunks.extend(scan_flow_scalar_spaces(double))
                chunks.extend(scan_flow_scalar_non_spaces(double))
            forward()
            # return ScalarToken(''.join(chunks), false, start_mark, end_mark,
            #         style)
            return Token.new("SCALAR", ''.join(chunks), false, style)


        static var escape_replacements = {
            '0':    '\u0003',
            '\"':   '\"',
            '\\':   '\\',
            '/':    '/',
            'L':    '\u2028',
            'P':    '\u2029',
        }

        static var escape_codes = {
            'x':    2,
            'u':    4,
            'U':    8,
        }

        func scan_flow_scalar_non_spaces(double):
            # See the specification for details.
            var chunks = []
            while true:
                var length = 0
                while peek(length) not in '\'\"\\\u0003 \t\r\n':
                    length += 1
                if length:
                    chunks.append(prefix(length))
                    forward(length)
                var ch = peek()
                if not double and ch == '\'' and peek(1) == '\'':
                    chunks.append('\'')
                    forward(2)
                elif (double and ch == '\'') or (not double and ch in '\"\\'):
                    chunks.append(ch)
                    forward()
                elif double and ch == '\\':
                    forward()
                    ch = peek()
                    if ch in escape_replacements:
                        chunks.append(escape_replacements[ch])
                        forward()
                    elif ch in escape_codes:
                        length = escape_codes[ch]
                        forward()
                        for k in range(length):
                            if peek(k) not in '0123456789ABCDEFabcdef':
                                Parser.error("while scanning a double-quoted scalar expected escape sequence of %d hexadecimal numbers, but found %c" % [length, peek(k)])
                        var code = prefix(length).hex_to_int()
                        chunks.append(char(code))
                        forward(length)
                    elif ch in '\r\n':
                        scan_line_break()
                        chunks.extend(scan_flow_scalar_breaks(double))
                    else:
                        Parser.error("while scanning a double-quoted scalar found unknown escape character %c" % ch)
                else:
                    return chunks

        func scan_flow_scalar_spaces(double):
            # See the specification for details.
            var chunks = []
            var length = 0
            while peek(length) in ' \t':
                length += 1
            var whitespaces = prefix(length)
            forward(length)
            var ch = peek()
            if ch == '\u0003':
                Parser.error("while scanning a quoted scalar found unexpected end of stream")
            elif ch in '\r\n':
                var line_break = scan_line_break()
                var breaks = scan_flow_scalar_breaks(double)
                if line_break != '\n':
                    chunks.append(line_break)
                elif not breaks:
                    chunks.append(' ')
                chunks.extend(breaks)
            else:
                chunks.append(whitespaces)
            return chunks

        func scan_flow_scalar_breaks(double):
            # See the specification for details.
            var chunks = []
            while true:
                # Instead of checking indentation, we check for document
                # separators.
                var prefix = prefix(3)
                if (prefix == '---' or prefix == '...')   \
                        and peek(3) in '\u0003 \t\r\n':
                    Parser.error("while scanning a quoted scalar found unexpected document separator")
                while peek() in ' \t':
                    forward()
                if peek() in '\r\n':
                    chunks.append(scan_line_break())
                else:
                    return chunks

        func scan_plain():
            # See the specification for details.
            # We add an additional restriction for the flow context:
            #   plain scalars in the flow context cannot contain ',' or '?'.
            # We also keep track of the `allow_simple_key` flag here.
            # Indentation rules are loosed for the flow context.
            var chunks = []
            # var start_mark = get_mark()
            # var end_mark = start_mark
            var indent = indent+1
            # We allow zero indentation for scalars, but then we need to check for
            # document separators at the beginning of the line.
            #if indent == 0:
            #    indent = 1
            var spaces = []
            while true:
                var length = 0

                if peek() == '#':
                    break
                while true:
                    var ch = peek(length)
                    if ch in '\u0003 \t\r\n'    \
                            or (ch == ':' and
                                    peek(length+1) in '\u0003 \t\r\n'
                                        + (',[]{}' if flow_level > 0 else ''))\
                            or (flow_level and ch in ',?[]{}'):
                        break
                    length += 1
                if length == 0:
                    break
                allow_simple_key = false
                chunks.append_array(spaces)
                chunks.append(prefix(length))
                forward(length)
                # end_mark = get_mark()
                spaces = scan_plain_spaces(indent)
                if spaces.is_empty() or peek() == '#' \
                        or (flow_level == 0 and column_index < indent):
                    break
            # return ScalarToken(''.join(chunks), true, start_mark, end_mark)
            return Token.new("SCALAR", ''.join(chunks), true)


        func scan_plain_spaces(indent):
            # See the specification for details.
            # The specification is really confusing about tabs in plain scalars.
            # We just forbid them completely. Do not use tabs in YAML!
            var chunks = []
            var length = 0
            while peek(length) in ' ':
                length += 1
            var whitespaces = prefix(length)
            forward(length)
            var ch = peek()
            if ch in '\r\n':
                var line_break = scan_line_break()
                allow_simple_key = true
                var prefix = prefix(3)
                if (prefix == '---' or prefix == '...')   \
                        and peek(3) in '\u0003 \t\r\n':
                    return
                var breaks = []
                while peek() in ' \r\n':
                    if peek() == ' ':
                        forward()
                    else:
                        breaks.append(scan_line_break())
                        prefix = prefix(3)
                        if (prefix == '---' or prefix == '...')   \
                                and peek(3) in '\u0003 \t\r\n':
                            return
                if line_break != '\n':
                    chunks.append(line_break)
                elif breaks.is_empty():
                    chunks.append(' ')
                chunks.append_array(breaks)
            elif not whitespaces.is_empty():
                chunks.append(whitespaces)
            return chunks

        func scan_tag_handle(name):
            # See the specification for details.
            # For some strange reasons, the specification does not allow '_' in
            # tag handles. I have allowed it anyway.
            var ch = peek()
            if ch != '!':
                # raise ScannerError("while scanning a %s" % name, start_mark,
                #         "expected '!', but found %r" % ch, get_mark())
                Parser.error("while scanning a %s expected '!', but found %c" % [name, ch])
            var length = 1
            ch = peek(length)
            if ch != ' ':
                while '0' <= ch <= '9' or 'A' <= ch <= 'Z' or 'a' <= ch <= 'z'  \
                        or ch in '-_':
                    length += 1
                    ch = peek(length)
                if ch != '!':
                    forward(length)
                    # raise ScannerError("while scanning a %s" % name, start_mark,
                    #         "expected '!', but found %r" % ch, get_mark())
                length += 1
            var value = prefix(length)
            forward(length)
            return value

        func scan_tag_uri(name):
            # See the specification for details.
            # Note: we do not check if URI is well-formed.
            var chunks = []
            var length = 0
            var ch = peek(length)
            while '0' <= ch <= '9' or 'A' <= ch <= 'Z' or 'a' <= ch <= 'z'  \
                    or ch in '-;/?:@&=+$,_.!~*\'()[]%':
                if ch == '%':
                    chunks.append(prefix(length))
                    forward(length)
                    length = 0
                    chunks.append(scan_uri_escapes(name))
                else:
                    length += 1
                ch = peek(length)
            if length:
                chunks.append(prefix(length))
                forward(length)
                length = 0
            if not chunks:
                # raise ScannerError("while parsing a %s" % name, start_mark,
                #         "expected URI, but found %r" % ch, get_mark())
                Parser.error("while parsing a %s expected URI, but found %c" % [name, ch])
            return ''.join(chunks)

        func scan_uri_escapes(name):
            # See the specification for details.
            var codes = []
            # var mark = get_mark()
            while peek() == '%':
                forward()
                for k in range(2):
                    if peek(k) not in '0123456789ABCDEFabcdef':
                        # raise ScannerError("while scanning a %s" % name, start_mark,
                        #         "expected URI escape sequence of 2 hexadecimal numbers, but found %r"
                        #         % peek(k), get_mark())
                        Parser.error("while scanning a %s expected URI escape sequence of 2 hexadecimal numbers, but found  %c" % [name, peek(k)])
                codes.append(prefix(2).hex_to_int())
                forward(2)

            var value = PackedByteArray(codes).get_string_from_utf8()
            # except UnicodeDecodeError as exc:
            #     raise ScannerError("while scanning a %s" % name, start_mark, str(exc), mark)
            return value


        func scan_line_break():
            var ch = peek()
            if ch == '\n':
                forward()
                return '\n'
            return ''
