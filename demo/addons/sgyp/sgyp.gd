@static_unload
# This annotation will not take effect due to an engine bug,
# but even so it should not cause any problems, SGYP does not use a lot of memory.
# for more detail: https://docs.godotengine.org/en/stable/classes/class_@gdscript.html#class-gdscript-annotation-static-unload


extends Node
# class_name SGYP extends RefCounted
# # You can replace the above comment and use SGYP like a normal class, 
# # but the plugin form allows you to decide whether to enable SGYP.

static func test_parse(yaml_data) -> Variant:
    var yaml_data_type :String = type_string(typeof(yaml_data))
    if yaml_data_type == "String":
        return SGYPaser.new().load(yaml_data.to_utf8_buffer())
    elif yaml_data_type == "PackedByteArray":
        return SGYPaser.new().load(yaml_data)
    elif yaml_data_type == "StreamPeerBuffer":
        return SGYPaser.new().load(yaml_data.data_array)
    else:
        SGYPaser.error("Unsupported YAML data type.")
        return null


class SGYPaser:

    func load(yaml_bytes:PackedByteArray) -> Variant:
        var yaml_string = match_bom_return_string(yaml_bytes)
        var tokens = Scanner.new(yaml_string).scan()
        var events = Parser.new(tokens).parse()
        # var nodes = Composer.new(events).compose()
        # var result = Constructor.new(nodes).construct()

        # for t in tokens:
        #     print(t.type)

        for e in events:
            print(e.type)

        return null

    static func soft_assert(condition: bool, message: String = "Soft assertion failed"):
        if not condition: push_error("SGYP Error: " + message)

    static func error(...messages):
        soft_assert(false, messages[0])

    static func warn(message: String = "Something is wrong"):
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
        var type    :String
        var name    :String
        var value   :String
        var plain   :bool
        var style   # String or null

        var start_mark  :Mark
        var end_mark    :Mark

        func _init(p_type:String, ...args) -> void:
            assert(p_type in valid_types, "Token type must be one of the valid_types")
            type = p_type

            match type:
                "DIRECTIVE":
                    name  = args[0]
                    value = args[1]
                    start_mark = args[2]
                    end_mark   = args[3]
                "ALIAS", "ANCHOR", "TAG":
                    value = args[0]
                    start_mark = args[1]
                    end_mark   = args[2]
                "SCALAR":
                    value = args[0]
                    plain = args[1]
                    style = args[2]
                    start_mark = args[3]
                    end_mark   = args[4]
                _: 
                    start_mark = args[0]
                    end_mark   = args[1]

    class Mark:
        static var source_name := "<unknown stream>"
        var yaml_string     :String
        var char_index      :int
        var line_index      :int
        var column_index    :int


        func _init(p_yaml_string, p_char_index, p_line_index, p_column_index):
            yaml_string = p_yaml_string
            char_index = p_char_index
            line_index = p_line_index
            column_index = p_column_index

        func get_snippet(indent = 4, max_length = 75):
            if yaml_string == null or yaml_string.is_empty():
                return null
            var head = ''
            var start = char_index
            while start > 0 and yaml_string[start-1] not in '\u0003\r\n':
                start -= 1
                if char_index-start > max_length/2-1:
                    head = ' ... '
                    start += 5
                    break
            var tail = ''
            var end = char_index
            while end < len(yaml_string) and yaml_string[end] not in '\u0003\r\n':
                end += 1
                if end-char_index > max_length/2-1:
                    tail = ' ... '
                    end -= 5
                    break
            var snippet = yaml_string.substr(start, end-start)
            return ' '*indent + head + snippet + tail + '\n'  \
                    + ' '*(indent+char_index-start+len(head)) + '^'

        func _to_string() -> String:
            var snippet = get_snippet()
            var where = "  in \"%s\", line %d, column %d"   \
                    % [source_name, line_index+1, column_index+1]
            if snippet != null:
                where += ":\n"+snippet
            return where

    class Scanner:
        # The Scanner behaves very similarly to PyYAML's Scanner and Reader, 
        # but SGYP doesn't need to handle streaming data, 
        # so it outputs the results (i.e tokens) to the SGYPaser all at once.

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

        func get_mark() -> Mark:
            return Mark.new(yaml_string, char_index, line_index, column_index)

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

        func scan():
            yaml_string = convert_line_breaks_to_only_line_break(yaml_string, '\n')
            yaml_string += "\u0003" # Adding an EOF makes the code simpler.

            while need_more_tokens:
                fetch_more_tokens()
            return tokens

        static func convert_line_breaks_to_only_line_break(text :String, only_line_break :String) -> String:
            # The key here is that we have to treat line_breaks as the same symbol
            # So first, We choose a single character line_break as the only_line_break( '\n' )
            # Then convert all line_breaks that are not only_line_break to only_line_break
            assert(line_breaks.has(only_line_break), "only_line_break should be one of line_breaks.")
            for line_break in line_breaks:
                if line_break != only_line_break:
                    text = only_line_break.join(text.split(line_break))
            return text

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
            SGYPaser.error("while scanning for the next token found character %c that cannot start any token %s" % [ch, get_mark()])

        # Simple keys treatment.

        # func next_possible_simple_key():
        #     # Return the number of the nearest possible simple key. Actually we
        #     # don't need to loop through the whole dictionary. We may replace it
        #     # with the following code:
        #     #   if not possible_simple_keys:
        #     #       return null
        #     #   return possible_simple_keys[
        #     #           min(possible_simple_keys.keys())].token_number
        #     min_token_number = null
        #     for level in possible_simple_keys:
        #         key = possible_simple_keys[level]
        #         if min_token_number is null or key.token_number < min_token_number:
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
                        SGYPaser.error("while scanning a simple key %s could not find expected ':' %s" 
                        % [key.mark, get_mark()])
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
                    "mark":get_mark()
                }
                possible_simple_keys[flow_level] = key

        func remove_possible_simple_key():
            # Remove the saved possible key position at the current flow level.
            if flow_level in possible_simple_keys:
                var key = possible_simple_keys[flow_level]
                
                if key.required:
                        SGYPaser.error("while scanning a simple key %s could not find expected ':' %s" % [key.mark, get_mark()])

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
            #    raise ScannerError(null, null,
            #            "invalid indentation or unclosed '[' or '{'",
            #            get_mark())

            # In the flow context, indentation is ignored. We make the scanner less
            # restrictive then specification requires.
            if flow_level > 0:
                return

            # In block context, we may need to issue the BLOCK-END tokens.
            while indent > column:
                indent = indents.pop_back()
                var mark = get_mark()
                tokens.append(Token.new("BLOCK_END", mark, mark))

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
            var mark = get_mark()
            tokens.append(Token.new("STREAM_START", mark, mark))

        func fetch_stream_end():

            # Set the current indentation to -1.
            unwind_indent(-1)

            # Reset simple keys.
            remove_possible_simple_key()
            allow_simple_key = false
            possible_simple_keys = {}
            
            # Add STREAM-END.
            var mark = get_mark()
            tokens.append(Token.new("STREAM_END", mark, mark))

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
            var start_mark = get_mark()
            forward(3)
            var end_mark = get_mark()
            tokens.append(Token.new(token_type, start_mark, end_mark))

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
            var start_mark = get_mark()
            forward()
            var end_mark = get_mark()
            tokens.append(Token.new(token_type, start_mark, end_mark))

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
            var start_mark = get_mark()
            forward()
            var end_mark = get_mark()
            tokens.append(Token.new(token_type, start_mark, end_mark))

        func fetch_flow_entry():

            # Simple keys are allowed after ','.
            allow_simple_key = true

            # Reset possible simple key on the current level.
            remove_possible_simple_key()

            # Add FLOW-ENTRY.
            var start_mark = get_mark()
            forward()
            var end_mark = get_mark()
            tokens.append(Token.new("FLOW_ENTRY", start_mark, end_mark))

        func fetch_block_entry():
            # Block context needs additional checks.
            if flow_level == 0:

                # Are we allowed to start a new entry?
                if not allow_simple_key:
                    SGYPaser.error("sequence entries are not allowed here." % get_mark())

                # We may need to add BLOCK-SEQUENCE-START.
                if add_indent(column_index):
                    var mark = get_mark()
                    tokens.append(Token.new("BLOCK_SEQUENCE_START", mark, mark))

            # It's an error for the block entry to occur in the flow context,
            # but we let the SGYPaser detect this.
            else:
                pass

            # Simple keys are allowed after '-'.
            allow_simple_key = true

            # Reset possible simple key on the current level.
            remove_possible_simple_key()
            # Add BLOCK-ENTRY.
            var start_mark = get_mark()
            forward()
            var end_mark = get_mark()
            tokens.append(Token.new("BLOCK_ENTRY", start_mark, end_mark))

        func fetch_key():
            
            # Block context needs additional checks.
            if flow_level == 0:

                # Are we allowed to start a key (not necessary a simple)?
                if not allow_simple_key:
                    SGYPaser.error("mapping keys are not allowed here" % get_mark())

                # We may need to add BLOCK-MAPPING-START.
                if add_indent(column_index):
                    var mark = get_mark()
                    tokens.append(Token.new("BLOCK_MAPPING_START", mark, mark))

            # Simple keys are allowed after '?' in the block context.
            allow_simple_key = flow_level == 0

            # Reset possible simple key on the current level.
            remove_possible_simple_key()

            # Add KEY.
            var start_mark = get_mark()
            forward()
            var end_mark = get_mark()
            tokens.append(Token.new("KEY", start_mark, end_mark))

        func fetch_value():

            # Do we determine a simple key?
            if flow_level in possible_simple_keys:

                # Add KEY.
                var key = possible_simple_keys[flow_level]
                possible_simple_keys.erase(flow_level)
                tokens.insert(key.token_number,
                        Token.new("KEY", key.mark, key.mark))

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
                # (Do we really need them? They will be caught by the SGYPaser
                # anyway.)
                if flow_level == 0:

                    # We are allowed to start a complex value if and only if
                    # we can start a simple key.
                    if not allow_simple_key:
                        SGYPaser.error("mapping values are not allowed here" % get_mark())

                # If this value starts a new block mapping, we need to add
                # BLOCK-MAPPING-START.  It will be detected as an error later by
                # the SGYPaser.
                if flow_level == 0:
                    if add_indent(column_index):
                        # tokens.append(BlockMappingStartToken(mark, mark))
                        tokens.append(Token.new("BLOCK_MAPPING_START"))


                # Simple keys are allowed after ':' in the block context.
                allow_simple_key = flow_level == 0

                # Reset possible simple key on the current level.
                remove_possible_simple_key()

            # Add VALUE.
            var start_mark = get_mark()
            forward()
            var end_mark = get_mark()
            tokens.append(Token.new("VALUE", start_mark, end_mark))

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
            var start_mark = get_mark()
            var end_mark = null
            forward()
            var name = scan_directive_name(start_mark)
            var value = null
            if name == 'YAML':
                value = scan_yaml_directive_value(start_mark)
                end_mark = get_mark()
            elif name == 'TAG':
                value = scan_tag_directive_value(start_mark)
                end_mark = get_mark()
            else:
                end_mark = get_mark()
                while peek() not in '\u0003\r\n':
                    forward()
            scan_directive_ignored_line(start_mark)
            return Token.new("DIRECTIVE", name, value, start_mark, end_mark)

        func scan_directive_name(start_mark):
            # See the specification for details.
            var length = 0
            var ch = peek(length)
            while '0' <= ch <= '9' or 'A' <= ch <= 'Z' or 'a' <= ch <= 'z'  \
                    or ch in '-_':
                length += 1
                ch = peek(length)
            if not length:
                SGYPaser.error("while scanning a directive %s expected alphabetic or numeric character, but found %c %s" 
                % [start_mark, ch, get_mark()])
            var value = prefix(length)
            forward(length)
            ch = peek()
            if ch not in '\u0003 \r\n':
                SGYPaser.error("while scanning a directive %s expected alphabetic or numeric character, but found %c %s" 
                % [start_mark, ch, get_mark()])

            return value

        func scan_yaml_directive_value(start_mark):
            # See the specification for details.
            while peek() in '\t ':
                forward()
            var major = scan_yaml_directive_number(start_mark)
            if peek() != '.':
                SGYPaser.error("while scanning YAML directive %s expected a digit or '.', but found %c %s" 
                % [start_mark, peek(), get_mark()])
            forward()
            var minor = scan_yaml_directive_number(start_mark)
            if peek() not in '\u0003 \r\n':
                SGYPaser.error("while scanning YAML directive %s expected a digit or ' ', but found %c %s" 
                % [start_mark, peek(), get_mark()])
            return [major, minor]

        func scan_yaml_directive_number(start_mark):
            # See the specification for details.
            var ch = peek()
            if not ('0' <= ch <= '9'):
                SGYPaser.error("while scanning YAML directive %s expected a digit, but found %c %s" 
                % [start_mark, peek(), get_mark()])
            var length = 0
            while '0' <= peek(length) <= '9':
                length += 1
            var value = int(prefix(length))
            forward(length)
            return value

        func scan_tag_directive_value(start_mark):
            # See the specification for details.
            while peek() == ' ':
                forward()
            var handle = scan_tag_directive_handle(start_mark)
            while peek() == ' ':
                forward()
            var prefix = scan_tag_directive_prefix(start_mark)
            return [handle, prefix]

        func scan_tag_directive_handle(start_mark):
            # See the specification for details.
            var value = scan_tag_handle('directive', start_mark)
            var ch = peek()
            if ch != ' ':
                SGYPaser.error("while scanning TAG directive %s expected ' ', but found %c %s" 
                % [start_mark, peek(), get_mark()])
            return value

        func scan_tag_directive_prefix(start_mark):
            # See the specification for details.
            var value = scan_tag_uri('directive', start_mark)
            var ch = peek()
            if ch not in '\u0003 \r\n':
                SGYPaser.error("while scanning TAG directive %s expected ' ', but found %c %s" 
                % [start_mark, peek(), get_mark()])
            return value

        func scan_directive_ignored_line(start_mark):
            # See the specification for details.
            while peek() == ' ':
                forward()
            if peek() == '#':
                while peek() not in '\u0003\r\n':
                    forward()
            var ch = peek()
            if ch not in '\u0003\r\n':
                SGYPaser.error("while scanning TAG directive %s expected a comment or a line break, but found %c %s" 
                % [start_mark, peek(), get_mark()])
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
            var start_mark = get_mark()
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
                SGYPaser.error("while scanning an %s %s expected alphabetic or numeric character, but found %c %s"
                        % [name, start_mark, ch, get_mark()])
            var value = prefix(length)
            forward(length)
            ch = peek()
            if ch not in '\u0003 \t\r\n?:,]}%@`':
                SGYPaser.error("while scanning an %s %s expected alphabetic or numeric character, but found %c %s"
                        % [name, start_mark, ch, get_mark()])

            var end_mark = get_mark()
            return Token.new(token_type, value, start_mark, end_mark)

        func scan_tag():
            # See the specification for details.
            var start_mark = get_mark()
            var ch = peek(1)
            var suffix
            var handle

            if ch == '<':
                handle = null
                forward(2)
                suffix = scan_tag_uri('tag', start_mark)
                if peek() != '>':
                    SGYPaser.error("while parsing a tag %s expected '>', but found %c %s" 
                    % [start_mark, peek(), get_mark()])
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
                    handle = scan_tag_handle('tag', start_mark)
                else:
                    handle = '!'
                    forward()
                suffix = scan_tag_uri('tag', start_mark)
            ch = peek()
            if ch not in '\u0003 \r\n':
                SGYPaser.error("while scanning a tag %s expected ' ', but found %c %s" 
                % [start_mark, ch, get_mark()])
            var value = [handle, suffix]
            var end_mark = get_mark()
            return Token.new("TAG", value, start_mark, end_mark)

        func scan_block_scalar(style):
            # See the specification for details.

            var folded = true if style == '>' else false

            var chunks = []
            var start_mark = get_mark()
            var end_mark

            # Scan the header.
            forward()
            var temp_dic  = scan_block_scalar_indicators(start_mark)
            var chomping  = temp_dic.chomping
            var increment = temp_dic.increment
            scan_block_scalar_ignored_line(start_mark)

            # Determine the indentation level and go to the first non-empty line.
            var min_indent = indent+1
            var breaks
            var indent

            if min_indent < 1:
                min_indent = 1
            if increment == null:
                temp_dic = scan_block_scalar_indentation()
                breaks = temp_dic.chunks
                end_mark = temp_dic.end_mark
                var max_indent = temp_dic.max_indent
                indent = max(min_indent, max_indent)
            else:
                indent = min_indent+increment-1
                temp_dic = scan_block_scalar_breaks(indent)
                breaks = temp_dic.chunks
                end_mark = temp_dic.end_mark
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
                temp_dic = scan_block_scalar_breaks(indent)
                breaks = temp_dic.chunks
                end_mark = temp_dic.end_mark
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
            return Token.new("SCALAR", ''.join(chunks), false, style, start_mark, end_mark)

        func scan_block_scalar_indicators(start_mark):
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
                        SGYPaser.error("while scanning a block scalar %s expected indentation indicator in the range 1-9, but found 0 %s"
                        % [start_mark, get_mark()])
                    forward()
            elif ch in '0123456789':
                increment = int(ch)
                if increment == 0:
                    SGYPaser.error("while scanning a block scalar %s expected indentation indicator in the range 1-9, but found 0 %s"
                    % [start_mark, get_mark()])
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
                SGYPaser.error("while scanning a block scalar %s expected chomping or indentation indicators, but found %c %s"
                % [start_mark, ch, get_mark()])
            return {"chomping":chomping, "increment":increment}

        func scan_block_scalar_ignored_line(start_mark):
            # See the specification for details.
            while peek() == ' ':
                forward()
            if peek() == '#':
                while peek() not in '\u0003\r\n':
                    forward()
            var ch = peek()
            if ch not in '\u0003\r\n':
                SGYPaser.error("while scanning a block scalar %s expected a comment or a line break, but found %c %s" 
                % [start_mark, ch, get_mark()])
            scan_line_break()

        func scan_block_scalar_indentation():
            # See the specification for details.
            var chunks = []
            var max_indent = 0
            var end_mark = get_mark()
            while peek() in ' \r\n':
                if peek() != ' ':
                    chunks.append(scan_line_break())
                    end_mark = get_mark()
                else:
                    forward()
                    if column_index > max_indent:
                        max_indent = column_index
            return {"chunks":chunks, "max_indent":max_indent, "end_mark":end_mark}

        func scan_block_scalar_breaks(indent):
            # See the specification for details.
            var chunks = []
            var end_mark = get_mark()
            while column_index < indent and peek() == ' ':
                forward()
            while peek() in '\r\n':
                chunks.append(scan_line_break())
                end_mark = get_mark()
                while column_index < indent and peek() == ' ':
                    forward()
            return {"chunks":chunks, "end_mark":end_mark}

        func scan_flow_scalar(style):
            # See the specification for details.
            # Note that we loose indentation rules for quoted scalars. Quoted
            # scalars don't need to adhere indentation because " and ' clearly
            # mark the beginning and the end of them. Therefore we are less
            # restrictive then the specification requires. We only need to check
            # that document separators are not included in scalars.
            var double = true if style == '"' else false
            var chunks = []
            var start_mark = get_mark()
            var quote = peek()
            forward()
            chunks.extend(scan_flow_scalar_non_spaces(double, start_mark))
            while peek() != quote:
                chunks.extend(scan_flow_scalar_spaces(double, start_mark))
                chunks.extend(scan_flow_scalar_non_spaces(double, start_mark))
            forward()
            var end_mark = get_mark()
            return Token.new("SCALAR", ''.join(chunks), false, style, start_mark, end_mark)


        const ESCAPE_REPLACEMENTS = {
            '0':    '\u0003',
            '\"':   '\"',
            '\\':   '\\',
            '/':    '/',
            'L':    '\u2028',
            'P':    '\u2029',
        }

        const ESCAPE_CODES = {
            'x':    2,
            'u':    4,
            'U':    8,
        }

        func scan_flow_scalar_non_spaces(double, start_mark):
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
                    if ch in ESCAPE_REPLACEMENTS:
                        chunks.append(ESCAPE_REPLACEMENTS[ch])
                        forward()
                    elif ch in ESCAPE_CODES:
                        length = ESCAPE_CODES[ch]
                        forward()
                        for k in range(length):
                            if peek(k) not in '0123456789ABCDEFabcdef':
                                SGYPaser.error("while scanning a double-quoted scalar %s expected escape sequence of %d hexadecimal numbers, but found %c %s" 
                                % [start_mark, length, peek(k), get_mark()])
                        var code = prefix(length).hex_to_int()
                        chunks.append(char(code))
                        forward(length)
                    elif ch in '\r\n':
                        scan_line_break()
                        chunks.extend(scan_flow_scalar_breaks(double, start_mark))
                    else:
                        SGYPaser.error("while scanning a double-quoted scalar %s found unknown escape character %c %s" 
                        % [start_mark, ch, get_mark()])
                else:
                    return chunks

        func scan_flow_scalar_spaces(double, start_mark):
            # See the specification for details.
            var chunks = []
            var length = 0
            while peek(length) in ' \t':
                length += 1
            var whitespaces = prefix(length)
            forward(length)
            var ch = peek()
            if ch == '\u0003':
                SGYPaser.error("while scanning a quoted scalar %s found unexpected end of stream %s" 
                % [start_mark, get_mark()])
            elif ch in '\r\n':
                var line_break = scan_line_break()
                var breaks = scan_flow_scalar_breaks(double, start_mark)
                if line_break != '\n':
                    chunks.append(line_break)
                elif not breaks:
                    chunks.append(' ')
                chunks.extend(breaks)
            else:
                chunks.append(whitespaces)
            return chunks

        func scan_flow_scalar_breaks(double, start_mark):
            # See the specification for details.
            var chunks = []
            while true:
                # Instead of checking indentation, we check for document
                # separators.
                var prefix = prefix(3)
                if (prefix == '---' or prefix == '...')   \
                        and peek(3) in '\u0003 \t\r\n':
                    SGYPaser.error("while scanning a quoted scalar %s found unexpected document separator %s"
                    % [start_mark, get_mark()])
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
            var start_mark = get_mark()
            var end_mark = start_mark
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
                end_mark = get_mark()
                spaces = scan_plain_spaces(indent, start_mark)
                if spaces.is_empty() or peek() == '#' \
                        or (flow_level == 0 and column_index < indent):
                    break
            return Token.new("SCALAR", ''.join(chunks), true, null, start_mark, end_mark)

        func scan_plain_spaces(indent, start_mark):
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

        func scan_tag_handle(name, start_mark):
            # See the specification for details.
            # For some strange reasons, the specification does not allow '_' in
            # tag handles. I have allowed it anyway.
            var ch = peek()
            if ch != '!':
                SGYPaser.error("while scanning a %s %s expected '!', but found %c %s" 
                % [name, start_mark, ch, get_mark()])
            var length = 1
            ch = peek(length)
            if ch != ' ':
                while '0' <= ch <= '9' or 'A' <= ch <= 'Z' or 'a' <= ch <= 'z'  \
                        or ch in '-_':
                    length += 1
                    ch = peek(length)
                if ch != '!':
                    forward(length)
                    SGYPaser.error("while scanning a %s %s expected '!', but found %c %s" 
                    % [name, start_mark, ch, get_mark()])
                length += 1
            var value = prefix(length)
            forward(length)
            return value

        func scan_tag_uri(name, start_mark):
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
                    chunks.append(scan_uri_escapes(name, start_mark))
                else:
                    length += 1
                ch = peek(length)
            if length:
                chunks.append(prefix(length))
                forward(length)
                length = 0
            if not chunks:
                SGYPaser.error("while parsing a %s %s expected URI, but found %c %s" 
                % [name, start_mark, ch, get_mark()])
            return ''.join(chunks)

        func scan_uri_escapes(name, start_mark):
            # See the specification for details.
            var codes = []
            # var mark = get_mark()
            while peek() == '%':
                forward()
                for k in range(2):
                    if peek(k) not in '0123456789ABCDEFabcdef':
                        SGYPaser.error("while scanning a %s %s expected URI escape sequence of 2 hexadecimal numbers, but found %c %s" 
                        % [name, start_mark, peek(k), get_mark()])
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

    class Event:
        # Parser produces events of the following types:
        # STREAM-START
        # STREAM-END
        # DOCUMENT-START(is_explicit, [yaml_version, tags])
        # DOCUMENT-END(is_explicit)
        # SEQUENCE-START(anchor, tag, implicit, [is_flow_style])
        # SEQUENCE-END
        # MAPPING-START(anchor, tag, implicit, is_flow_style)
        # MAPPING-END
        # ALIAS(value)
        # SCALAR(anchor, tag, implicit, value, style)
        static var valid_types := [
            "STREAM_START"  , "STREAM_END",
            "DOCUMENT_START", "DOCUMENT_END",
            "SEQUENCE_START", "SEQUENCE_END",
            "MAPPING_START" , "MAPPING_END",
            "ALIAS", "SCALAR"
            ]

        var type :String

        var is_explicit   :bool
        var yaml_version  # Array[int] or null # version 1.2 will be [1, 2]
        var tags          # Dictionary or null

        var anchor        # String
        var tag           # Array[String], [handle, suffix]
        var implicit      # bool or Array[bool], strange...
        var is_flow_style # bool or null

        var value :String
        var style # String or null

        var start_mark  :Mark
        var end_mark    :Mark
        
        func _init(p_type:String, ...args):
            assert(p_type in valid_types, "Event type must be one of the valid_types")
            type = p_type

            match type:
                "DOCUMENT_START":
                    is_explicit = args[0]
                    if args.size() == 3+2: # +2 Mark args
                        yaml_version = args[1]
                        tags = args[2]
                "DOCUMENT_END":
                    is_explicit = args[0]
                "SEQUENCE_START":
                    anchor = args[0]
                    tag = args[1]
                    implicit = args[2]
                    if args.size() == 4+2:
                        is_flow_style = args[3]
                "MAPPING_START":
                    anchor = args[0]
                    tag = args[1]
                    implicit = args[2]
                    is_flow_style = args[3]
                "ALIAS":
                    value = args[0]
                "SCALAR":
                    anchor = args[0]
                    tag = args[1]
                    implicit = args[2]
                    value = args[3]
                    style = args[4]

            start_mark = args[-2]
            end_mark = args[-1]


    class Parser:
        const DEFAULT_TAGS = {
            "!" : "!",
            "!!" : 'tag:yaml.org,2002:'
        }

        var current_event = null
        var yaml_version = null
        var tag_handles = {}
        var states = []
        var marks = []
        var state = parse_stream_start # Callable or null

        var tokens = []
        var tokens_taken = 0

        func _init(p_tokens):
            tokens = p_tokens

        func get_token():
            var result = null
            if tokens_taken < tokens.size():
                result = tokens[tokens_taken]
                tokens_taken += 1
            return result

        func check_token(...token_types):
            var current_token = peek_token()
            if not tokens.is_empty() and current_token != null:
                if current_token.type in token_types:
                    return true
            return false

        func peek_token():
            # Return null if no more tokens.
            return tokens[tokens_taken] if tokens_taken < tokens.size() else null

        func parse():
            var events = []
            while state != null:
                events.append(state.call())
            return events

        # func check_event(event_types :Array[String]):
        #     # Check the type of the next event.
        #     if current_event == null:
        #         if state.is_valid():
        #             current_event = state.call()
        #     if current_event != null:
        #         for type in event_types:
        #             if current_event.type == type:
        #                 return true
        #     return false

        # func peek_event():
        #     # Get the next event.
        #     if current_event != null:
        #         if state.is_valid():
        #             current_event = state.call()
        #     return current_event

        # func get_event():
        #     # Get the next event and proceed further.
        #     if current_event != null:
        #         if state.is_valid():
        #             current_event = state.call()
        #     var value = current_event
        #     current_event = null
        #     return value

        # stream    ::= STREAM-START implicit_document? explicit_document* STREAM-END
        # implicit_document ::= block_node DOCUMENT-END*
        # explicit_document ::= DIRECTIVE* DOCUMENT-START block_node? DOCUMENT-END*

        func parse_stream_start():

            # Parse the stream start.
            var token = get_token()
            var event = Event.new("STREAM_START", token.start_mark, token.end_mark)

            # Prepare the next state.
            state = parse_implicit_document_start

            return event

        func parse_implicit_document_start():

            # Parse an implicit document.
            if not check_token("DIRECTIVE", "DOCUMENT_START", "STREAM_END"):
                var tag_handles = DEFAULT_TAGS
                var token = peek_token()
                var is_explicit = false
                var event = Event.new("DOCUMENT_START", is_explicit, token.start_mark, token.end_mark)

                # Prepare the next state.
                states.append(parse_document_end)
                state = parse_block_node

                return event

            else:
                return parse_document_start()

        func parse_document_start():

            # Parse any extra document end indicators.
            while check_token("DOCUMENT_END"):
                get_token()

            # Parse an explicit document.
            var event
            if not check_token("STREAM_END"):
                var token = peek_token()
                var start_mark = token.start_mark
                var temp_array = process_directives()
                var version = temp_array[0]
                var tags = temp_array[1]
                if not check_token("DOCUMENT_START"):
                    SGYPaser.error("expected '<document start>', but found %s" % token.type,
                            token.start_mark)
                token = get_token()
                var end_mark = token.end_mark
                var is_explicit = true
                event = Event.new("DOCUMENT_START", is_explicit, version, tags, start_mark, end_mark)
                states.append(parse_document_end)
                state = parse_document_content
            else:
                # Parse the end of the stream.
                var token = get_token()
                event = Event.new("STREAM_END", token.start_mark, token.end_mark)
                assert(states.is_empty())
                assert(marks.is_empty())
                state = null
            return event

        func parse_document_end():

            # Parse the document end.
            var token = peek_token()
            var start_mark = token.start_mark
            var end_mark = token.end_mark
            var is_explicit = false
            if check_token("DOCUMENT_END"):
                token = get_token()
                end_mark = token.end_mark
                is_explicit = true
            var event = Event.new("DOCUMENT_END", is_explicit, start_mark, end_mark)

            # Prepare the next state.
            state = parse_document_start

            return event

        func parse_document_content():
            if check_token("DIRECTIVE",
                    "DOCUMENT_START", "DOCUMENT_END", "STREAM_END"):
                var event = process_empty_scalar(peek_token().start_mark)
                state = states.pop_back()
                return event
            else:
                return parse_block_node()

        func process_directives():
            yaml_version = null
            tag_handles = {}
            while check_token("DIRECTIVE"):
                var token = get_token()
                if token.name == 'YAML':
                    if yaml_version != null:
                        SGYPaser.error("found duplicate YAML directive", token.start_mark)
                    var major = token.value[0]
                    var minor = token.value[1]
                    if major != 1:
                        SGYPaser.error("found incompatible YAML document (version 1.* is required)",
                                token.start_mark)
                    yaml_version = token.value
                elif token.name == 'TAG':
                    var handle = token.value[0]
                    var prefix = token.value[1]
                    if handle in tag_handles:
                        SGYPaser.error(null, null,
                                "duplicate tag handle %r" % handle,
                                token.start_mark)
                    tag_handles[handle] = prefix

            var value
            if not tag_handles.is_empty():
                value = [yaml_version, tag_handles.duplicate()]
            else:
                value = [yaml_version, null]
            for key in DEFAULT_TAGS:
                if key not in tag_handles:
                    tag_handles[key] = DEFAULT_TAGS[key]
            return value

        # block_node_or_indentless_sequence ::= ALIAS
        #               | properties (block_content | indentless_block_sequence)?
        #               | block_content
        #               | indentless_block_sequence
        # block_node    ::= ALIAS
        #                   | properties block_content?
        #                   | block_content
        # flow_node     ::= ALIAS
        #                   | properties flow_content?
        #                   | flow_content
        # properties    ::= TAG ANCHOR? | ANCHOR TAG?
        # block_content     ::= block_collection | flow_collection | SCALAR
        # flow_content      ::= flow_collection | SCALAR
        # block_collection  ::= block_sequence | block_mapping
        # flow_collection   ::= flow_sequence | flow_mapping

        func parse_block_node():
            var is_block = true
            return parse_node(is_block)

        func parse_flow_node():
            return parse_node()

        func parse_block_node_or_indentless_sequence():
            var is_block = true
            var is_indentless_sequence = true
            return parse_node(is_block, is_indentless_sequence)

        func parse_node(is_block = false, is_indentless_sequence = false):
            var event
            var tag
            var anchor
            if check_token("ALIAS"):
                var token = get_token()
                event = Event.new("ALIAS", token.value, token.start_mark, token.end_mark)
                state = states.pop_back()
            else:
                var start_mark = null
                var end_mark = null
                var tag_mark = null
                if check_token("ANCHOR"):
                    var token = get_token()
                    start_mark = token.start_mark
                    end_mark = token.end_mark
                    anchor = token.value
                    if check_token("TAG"):
                        token = get_token()
                        tag_mark = token.start_mark
                        end_mark = token.end_mark
                        tag = token.value
                elif check_token("TAG"):
                    var token = get_token()
                    start_mark = token.start_mark
                    tag_mark = token.start_mark
                    end_mark = token.end_mark
                    tag = token.value
                    if check_token("ANCHOR"):
                        token = get_token()
                        end_mark = token.end_mark
                        anchor = token.value
                if tag != null:
                    var handle = tag[0]
                    var suffix = tag[1]
                    if handle != null:
                        if handle not in tag_handles:
                            SGYPaser.error("while parsing a node", start_mark,
                                    "found undefined tag handle %s" % handle,
                                    tag_mark)
                        tag = tag_handles[handle]+suffix
                    else:
                        tag = suffix
                #if tag == '!':
                #    SGYPaser.error("while parsing a node", start_mark,
                #            "found non-specific tag '!'", tag_mark,
                #            "Please check 'http://pyyaml.org/wiki/YAMLNonSpecificTag' and share your opinion.")
                if start_mark == null:
                    start_mark = peek_token().start_mark
                    end_mark = peek_token().start_mark
                event = null
                var implicit = (tag == null or tag == '!')
                if is_indentless_sequence and check_token("BLOCK_ENTRY"):
                    end_mark = peek_token().end_mark
                    event = Event.new("SEQUENCE_START", anchor, tag, implicit,
                            start_mark, end_mark)
                    state = parse_indentless_sequence_entry
                else:
                    if check_token("SCALAR"):
                        var token = get_token()
                        end_mark = token.end_mark
                        if (token.plain and tag == null) or tag == '!':
                            implicit = [true, false]
                        elif tag == null:
                            implicit = [false, true]
                        else:
                            implicit = [false, false]
                        event = Event.new("SCALAR", anchor, tag, implicit, token.value, token.style,
                                start_mark, end_mark)
                        state = states.pop_back()
                    elif check_token("FLOW_SEQUENCE_START"):
                        end_mark = peek_token().end_mark
                        var flow_style = true
                        event = Event.new("SEQUENCE_START", anchor, tag, implicit, flow_style,
                                start_mark, end_mark)
                        state = parse_flow_sequence_first_entry
                    elif check_token("FLOW_MAPPING_START"):
                        end_mark = peek_token().end_mark
                        var flow_style = true
                        event = Event.new("MAPPING_START", anchor, tag, implicit, flow_style,
                                start_mark, end_mark)
                        state = parse_flow_mapping_first_key
                    elif is_block and check_token("BLOCK_SEQUENCE_START"):
                        end_mark = peek_token().start_mark
                        var flow_style = false
                        event = Event.new("SEQUENCE_START", anchor, tag, implicit, flow_style,
                                start_mark, end_mark)
                        state = parse_block_sequence_first_entry
                    elif is_block and check_token("BLOCK_MAPPING_START"):
                        end_mark = peek_token().start_mark
                        var flow_style = false
                        event = Event.new("MAPPING_START", anchor, tag, implicit, flow_style,
                                start_mark, end_mark)
                        state = parse_block_mapping_first_key
                    elif anchor != null or tag != null:
                        # Empty scalars are allowed even if a tag or an anchor is
                        # specified.
                        event = Event.new("SCALAR", anchor, tag, [implicit, false], '', null,
                                start_mark, end_mark)
                        state = states.pop_back()
                    else:
                        var node_type = 'block' if is_block else 'flow'
                        var token = peek_token()
                        SGYPaser.error("while parsing a %s node" % node_type, start_mark,
                                "expected the node content, but found %s" % token.type,
                                token.start_mark)
            return event

        # block_sequence ::= BLOCK-SEQUENCE-START (BLOCK-ENTRY block_node?)* BLOCK-END

        func parse_block_sequence_first_entry():
            var token = get_token()
            marks.append(token.start_mark)
            return parse_block_sequence_entry()

        func parse_block_sequence_entry():
            var token
            if check_token("BLOCK_ENTRY"):
                token = get_token()
                if not check_token("BLOCK_ENTRY", "BLOCK_END"):
                    states.append(parse_block_sequence_entry)
                    return parse_block_node()
                else:
                    state = parse_block_sequence_entry
                    return process_empty_scalar(token.end_mark)
            if not check_token("BLOCK_END"):
                token = peek_token()
                SGYPaser.error("while parsing a block collection", marks[-1],
                        "expected <block end>, but found %r" % token.id, token.start_mark)
            token = get_token()
            var event = Event.new("SEQUENCE_END", token.start_mark, token.end_mark)
            state = states.pop_back()
            marks.pop_back()
            return event

        # indentless_sequence ::= (BLOCK-ENTRY block_node?)+

        func parse_indentless_sequence_entry():
            if check_token("BLOCK_ENTRY"):
                var token = get_token()
                if not check_token("BLOCK_ENTRY",
                        "KEY", "VALUE", "BLOCK_END"):
                    states.append(parse_indentless_sequence_entry)
                    return parse_block_node()
                else:
                    state = parse_indentless_sequence_entry
                    return process_empty_scalar(token.end_mark)
            var token = peek_token()
            var event = Event.new("SEQUENCE_END", token.start_mark, token.start_mark)
            state = states.pop_back()
            return event

        # block_mapping     ::= BLOCK-MAPPING_START
        #                       ((KEY block_node_or_indentless_sequence?)?
        #                       (VALUE block_node_or_indentless_sequence?)?)*
        #                       BLOCK-END

        func parse_block_mapping_first_key():
            var token = get_token()
            marks.append(token.start_mark)
            return parse_block_mapping_key()

        func parse_block_mapping_key():
            var token
            if check_token("KEY"):
                token = get_token()
                if not check_token("KEY", "VALUE", "BLOCK_END"):
                    states.append(parse_block_mapping_value)
                    return parse_block_node_or_indentless_sequence()
                else:
                    state = parse_block_mapping_value
                    return process_empty_scalar(token.end_mark)
            if not check_token("BLOCK_END"):
                token = peek_token()
                SGYPaser.error("while parsing a block mapping", marks[-1],
                        "expected <block end>, but found %r" % token.id, token.start_mark)
            token = get_token()
            var event = Event.new("MAPPING_END", token.start_mark, token.end_mark)
            state = states.pop_back()
            marks.pop_back()
            return event

        func parse_block_mapping_value():
            if check_token("VALUE"):
                var token = get_token()
                if not check_token("KEY", "VALUE", "BLOCK_END"):
                    states.append(parse_block_mapping_key)
                    return parse_block_node_or_indentless_sequence()
                else:
                    state = parse_block_mapping_key
                    return process_empty_scalar(token.end_mark)
            else:
                state = parse_block_mapping_key
                var token = peek_token()
                return process_empty_scalar(token.start_mark)

        # flow_sequence     ::= FLOW-SEQUENCE-START
        #                       (flow_sequence_entry FLOW-ENTRY)*
        #                       flow_sequence_entry?
        #                       FLOW-SEQUENCE-END
        # flow_sequence_entry   ::= flow_node | KEY flow_node? (VALUE flow_node?)?
        #
        # Note that while production rules for both flow_sequence_entry and
        # flow_mapping_entry are equal, their interpretations are different.
        # For `flow_sequence_entry`, the part `KEY flow_node? (VALUE flow_node?)?`
        # generate an inline mapping (set syntax).

        func parse_flow_sequence_first_entry():
            var token = get_token()
            marks.append(token.start_mark)
            var first = true
            return parse_flow_sequence_entry(first)

        func parse_flow_sequence_entry(first=false):
            if not check_token("FLOW_SEQUENCE_END"):
                if not first:
                    if check_token("FLOW_ENTRY"):
                        get_token()
                    else:
                        var token = peek_token()
                        SGYPaser.error("while parsing a flow sequence", marks[-1],
                                "expected ',' or ']', but got %r" % token.id, token.start_mark)
                
                if check_token("KEY"):
                    var token = peek_token()
                    var flow_style = true
                    var event = Event.new("MAPPING_START", null, null, true, flow_style,
                            token.start_mark, token.end_mark)
                    state = parse_flow_sequence_entry_mapping_key
                    return event
                elif not check_token("FLOW_SEQUENCE_END"):
                    states.append(parse_flow_sequence_entry)
                    return parse_flow_node()
            var token = get_token()
            var event = Event.new("SEQUENCE_END", token.start_mark, token.end_mark)
            state = states.pop_back()
            marks.pop_back()
            return event

        func parse_flow_sequence_entry_mapping_key():
            var token = get_token()
            if not check_token("VALUE",
                    "FLOW_ENTRY", "FLOW_SEQUENCE_END"):
                states.append(parse_flow_sequence_entry_mapping_value)
                return parse_flow_node()
            else:
                state = parse_flow_sequence_entry_mapping_value
                return process_empty_scalar(token.end_mark)

        func parse_flow_sequence_entry_mapping_value():
            if check_token("VALUE"):
                var token = get_token()
                if not check_token("FLOW_ENTRY", "FLOW_SEQUENCE_END"):
                    states.append(parse_flow_sequence_entry_mapping_end)
                    return parse_flow_node()
                else:
                    state = parse_flow_sequence_entry_mapping_end
                    return process_empty_scalar(token.end_mark)
            else:
                state = parse_flow_sequence_entry_mapping_end
                var token = peek_token()
                return process_empty_scalar(token.start_mark)

        func parse_flow_sequence_entry_mapping_end():
            state = parse_flow_sequence_entry
            var token = peek_token()
            return Event.new("MAPPING_END", token.start_mark, token.start_mark)

        # flow_mapping  ::= FLOW-MAPPING-START
        #                   (flow_mapping_entry FLOW-ENTRY)*
        #                   flow_mapping_entry?
        #                   FLOW-MAPPING-END
        # flow_mapping_entry    ::= flow_node | KEY flow_node? (VALUE flow_node?)?

        func parse_flow_mapping_first_key():
            var token = get_token()
            marks.append(token.start_mark)
            var first = true
            return parse_flow_mapping_key(first)

        func parse_flow_mapping_key(first=false):
            if not check_token("FLOW_MAPPING_END"):
                if not first:
                    if check_token("FLOW_ENTRY"):
                        get_token()
                    else:
                        var token = peek_token()
                        SGYPaser.error("while parsing a flow mapping", marks[-1],
                                "expected ',' or '}', but got %r" % token.id, token.start_mark)
                if check_token("KEY"):
                    var token = get_token()
                    if not check_token("VALUE",
                            "FLOW_ENTRY", "FLOW_MAPPING_END"):
                        states.append(parse_flow_mapping_value)
                        return parse_flow_node()
                    else:
                        state = parse_flow_mapping_value
                        return process_empty_scalar(token.end_mark)
                elif not check_token("FLOW_MAPPING_END"):
                    states.append(parse_flow_mapping_empty_value)
                    return parse_flow_node()
            var token = get_token()
            var event = Event.new("MAPPING_END", token.start_mark, token.end_mark)
            state = states.pop_back()
            marks.pop_back()
            return event

        func parse_flow_mapping_value():
            if check_token("VALUE"):
                var token = get_token()
                if not check_token("FLOW_ENTRY", "FLOW_MAPPING_END"):
                    states.append(parse_flow_mapping_key)
                    return parse_flow_node()
                else:
                    state = parse_flow_mapping_key
                    return process_empty_scalar(token.end_mark)
            else:
                state = parse_flow_mapping_key
                var token = peek_token()
                return process_empty_scalar(token.start_mark)

        func parse_flow_mapping_empty_value():
            state = parse_flow_mapping_key
            return process_empty_scalar(peek_token().start_mark)

        func process_empty_scalar(mark):
            return Event.new("SCALAR", null, null, [true, false], '', null, mark, mark)
