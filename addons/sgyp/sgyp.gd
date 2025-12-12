@static_unload
# This annotation will not take effect due to an engine bug,
# but even so it should not cause any problems, SGYP does not use a lot of memory.
# for more detail: https://docs.godotengine.org/en/stable/classes/class_@gdscript.html#class-gdscript-annotation-static-unload


# class_name SGYP extends Node
class_name SGYP extends RefCounted
# # You can replace the above comment and use SGYP like a normal class, 
# # but the plugin form allows you to decide whether to enable SGYP.

static func parse(yaml_data) -> Variant:
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

static func dump(p_var:Variant):
    print(p_var)
    SGYPaser.new().dump(p_var)

class SGYPaser:
    func _init():
        Resolver.init_yaml_implicit_resolvers()
        Constructor.init_yaml_constructors()
        Representer.init_yaml_representers()
        Serializer.set_up()
        Emitter.set_up()

    func load(yaml_bytes:PackedByteArray) -> Variant:
        var yaml_string = match_bom_return_string(yaml_bytes)
        var tokens = Scanner.new(yaml_string).scan()
        var result = Constructor.new(Composer.new(Parser.new(tokens))).get_single_data()

        return result

    func dump(p_var:Variant):
        Emitter.stream = StreamWrapper.new()
        Serializer.open()
        Representer.represent(p_var)
        Serializer.close()
        Emitter.stream.print_data()

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


    # Load Part

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

        # and '' is not supported.

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
                    "char_index":char_index,
                    "column_index":column_index,
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
                    if add_indent(key.column_index):
                        tokens.insert(key.token_number,
                                Token.new("BLOCK_MAPPING_START", key.mark, key.mark))

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
                        var mark = get_mark()
                        tokens.append(Token.new("BLOCK_MAPPING_START", mark, mark))


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
            while ('0' <= ch and ch <= '9') or ('A' <= ch and ch <= 'Z') or ('a' <= ch and ch <= 'z')  \
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
            while ('0' <= ch and ch <= '9') or ('A' <= ch and ch <= 'Z') or ('a' <= ch and ch <= 'z')  \
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
                while ('0' <= ch and ch <= '9') or ('A' <= ch and ch <= 'Z') or ('a' <= ch and ch <= 'z')  \
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
            while ('0' <= ch and ch <= '9') or ('A' <= ch and ch <= 'Z') or ('a' <= ch and ch <= 'z')  \
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
        var implicit      # bool or Array[bool]. Only for SCALAR, implicit is a Boolean array.
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

            if args.size() > 2 and \
                (is_instance_of(args[-2], Mark) and is_instance_of(args[-1], Mark)):

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
 
        func check_event(...event_types):
            # Check the type of the next event.
            if current_event == null:
                if state != null and state.is_valid():
                    current_event = state.call()
            if current_event != null:
                for type in event_types:
                    if current_event.type == type:
                        return true
            return false

        func peek_event():
            # Get the next event.
            if current_event == null:
                if state != null and state.is_valid():
                    current_event = state.call()
            return current_event

        func get_event():
            # Get the next event and proceed further.
            if current_event == null:
                if state != null and state.is_valid():
                    current_event = state.call()
            var value = current_event
            current_event = null
            return value

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

    class YAMLNode:
        # Composer produces nodes of the following types:
        # SEQUENCE(tag, value, is_flow_style)
        # MAPPING(tag, value, is_flow_style)
        # SCALAR(tag, value, style)
        static var valid_types := [
            "SEQUENCE",
            "MAPPING",
            "SCALAR"
            ]

        var type

        var tag
        var value
        var is_flow_style :bool
        var style

        var start_mark :Mark
        var end_mark :Mark

        func _init(p_type, ...args):
            assert(p_type in valid_types, "YAMLNode type must be one of the valid_types")
            type = p_type

            match type:
                "SEQUENCE", "MAPPING":
                    tag = args[0]
                    value = args[1]
                    is_flow_style = args[2]
                "SCALAR":
                    tag = args[0]
                    value = args[1]
                    style = args[2]

            if args.size() > 2 and \
                (is_instance_of(args[-2], Mark) and is_instance_of(args[-1], Mark)):

                start_mark = args[-2]
                end_mark = args[-1]

    class Composer:
        var anchors = {}

        var parser :Parser

        func _init(p_parser):
            parser = p_parser

        func check_node():
            # Drop the STREAM-START event.
            if parser.check_event("STREAM_START"):
                parser.get_event()

            # If there are more documents available?
            return not parser.check_event("STREAM_END")

        func get_node():
            # Get the root node of the next document.
            if not parser.check_event("STREAM_END"):
                return compose_document()

        func get_single_node():
            # Drop the STREAM-START event.
            parser.get_event()

            # Compose a document if the stream is not empty.
            var document = null
            if not parser.check_event("STREAM_END"):
                document = compose_document()

            # Ensure that the stream contains no more documents.
            if not parser.check_event("STREAM_END"):
                var event = parser.get_event()
                SGYPaser.error("expected a single document in the stream",
                        document.start_mark, "but found another document",
                        event.start_mark)

            # Drop the STREAM-END event.
            parser.get_event()

            return document

        func compose_document():
            # Drop the DOCUMENT-START event.
            parser.get_event()

            # Compose the root node.
            var node = compose_node(null, null)

            # Drop the DOCUMENT-END event.
            parser.get_event()

            anchors = {}
            return node

        func compose_node(parent, index):
            var event
            var anchor
            if parser.check_event("ALIAS"):
                event = parser.get_event()
                anchor = event.anchor
                if anchor not in anchors:
                    SGYPaser.error("found undefined alias %r"
                            % anchor, event.start_mark)
                return anchors[anchor]
            event = parser.peek_event()
            anchor = event.anchor
            if anchor != null:
                if anchor in anchors:
                    SGYPaser.error("found duplicate anchor %r; first occurrence"
                            % anchor, anchors[anchor].start_mark,
                            "second occurrence", event.start_mark)

            var node
            Resolver.descend_resolver(parent, index)
            if parser.check_event("SCALAR"):
                node = compose_scalar_node(anchor)
            elif parser.check_event("SEQUENCE_START"):
                node = compose_sequence_node(anchor)
            elif parser.check_event("MAPPING_START"):
                node = compose_mapping_node(anchor)
            Resolver.ascend_resolver()
            return node

        func compose_scalar_node(anchor):
            var event = parser.get_event()
            var tag = event.tag
            if tag == null or tag == '!':
                tag = Resolver.resolve("SCALAR", event.value, event.implicit)
            var node = YAMLNode.new("SCALAR", tag, event.value, event.style,
                    event.start_mark, event.end_mark)
            if anchor != null:
                anchors[anchor] = node
            return node

        func compose_sequence_node(anchor):
            var start_event = parser.get_event()
            var tag = start_event.tag
            if tag == null or tag == '!':
                tag = Resolver.resolve("SEQUENCE", null, start_event.implicit)
            var node = YAMLNode.new("SEQUENCE", tag, [], start_event.is_flow_style,
                    start_event.start_mark, null)
            if anchor != null:
                anchors[anchor] = node
            var index = 0
            while not parser.check_event("SEQUENCE_END"):
                node.value.append(compose_node(node, index))
                index += 1
            var end_event = parser.get_event()
            node.end_mark = end_event.end_mark
            return node

        func compose_mapping_node(anchor):
            var start_event = parser.get_event()
            var tag = start_event.tag
            if tag == null or tag == '!':
                tag = Resolver.resolve("MAPPING", null, start_event.implicit)
            var node = YAMLNode.new("MAPPING", tag, [], start_event.is_flow_style,
                    start_event.start_mark, null)
            if anchor != null:
                anchors[anchor] = node
            while not parser.check_event("MAPPING_END"):
                #key_event = parser.peek_event()
                var item_key = compose_node(node, null)
                #if item_key in node.value:
                #    SGYPaser.error("while composing a mapping", start_event.start_mark,
                #            "found duplicate key", key_event.start_mark)
                var item_value = compose_node(node, item_key)
                #node.value[item_key] = item_value
                node.value.append([item_key, item_value])
            var end_event = parser.get_event()
            node.end_mark = end_event.end_mark
            return node

    # NOTE: This class might need to be completely rewritten...
    class Resolver:
        const DEFAULT_SCALAR_TAG    = 'tag:yaml.org,2002:str'
        const DEFAULT_SEQUENCE_TAG  = 'tag:yaml.org,2002:seq'
        const DEFAULT_MAPPING_TAG   = 'tag:yaml.org,2002:map'

        static var yaml_implicit_resolvers = {}
        static var yaml_path_resolvers = {}

        static var resolver_exact_paths = []
        static var resolver_prefix_paths = []

        static func init_yaml_implicit_resolvers():
            Resolver.add_implicit_resolver(
                    'tag:yaml.org,2002:bool',
                    RegEx.create_from_string(r'''(?x)^(?:yes|Yes|YES|no|No|NO
                                |true|True|TRUE|false|False|FALSE
                                |on|On|ON|off|Off|OFF)$'''),
                    'yYnNtTfFoO'.split())

            Resolver.add_implicit_resolver(
                    'tag:yaml.org,2002:float',
                    RegEx.create_from_string(r'''(?x)^(?:[-+]?(?:[0-9][0-9_]*)\.[0-9_]*(?:[eE][-+][0-9]+)?
                                |\.[0-9][0-9_]*(?:[eE][-+][0-9]+)?
                                |[-+]?[0-9][0-9_]*(?::[0-5]?[0-9])+\.[0-9_]*
                                |[-+]?\.(?:inf|Inf|INF)
                                |\.(?:nan|NaN|NAN))$'''),
                    '-+0123456789.'.split())

            Resolver.add_implicit_resolver(
                    'tag:yaml.org,2002:int',
                    RegEx.create_from_string(r'''(?x)^(?:[-+]?0b[0-1_]+
                                |[-+]?0[0-7_]+
                                |[-+]?(?:0|[1-9][0-9_]*)
                                |[-+]?0x[0-9a-fA-F_]+
                                |[-+]?[1-9][0-9_]*(?::[0-5]?[0-9])+)$'''),
                    '-+0123456789'.split())

            Resolver.add_implicit_resolver(
                    'tag:yaml.org,2002:merge',
                    RegEx.create_from_string(r'^(?:<<)$'),
                    ['<'])

            Resolver.add_implicit_resolver(
                    'tag:yaml.org,2002:null',
                    RegEx.create_from_string(r'''(?x)^(?: ~
                                |null|Null|NULL
                                | )$'''),
                    ['~', 'n', 'N', ''])

            Resolver.add_implicit_resolver(
                    'tag:yaml.org,2002:timestamp',
                    RegEx.create_from_string(r'''(?x)^(?:[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]
                                |[0-9][0-9][0-9][0-9] -[0-9][0-9]? -[0-9][0-9]?
                                (?:[Tt]|[ \t]+)[0-9][0-9]?
                                :[0-9][0-9] :[0-9][0-9] (?:\.[0-9]*)?
                                (?:[ \t]*(?:Z|[-+][0-9][0-9]?(?::[0-9][0-9])?))?)$'''),
                    '0123456789'.split())

            Resolver.add_implicit_resolver(
                    'tag:yaml.org,2002:value',
                    RegEx.create_from_string(r'^(?:=)$'),
                    ['='])

            # The following resolver is only for documentation purposes. It cannot work
            # because plain scalars cannot start with '!', '&', or '*'.
            Resolver.add_implicit_resolver(
                    'tag:yaml.org,2002:yaml',
                    RegEx.create_from_string(r'^(?:!|&|\*)$'),
                    '!&*'.split())

        static func add_implicit_resolver(tag, regexp, first):
            # if not 'yaml_implicit_resolvers' in cls.__dict__:
            #     implicit_resolvers = {}
            #     for key in cls.yaml_implicit_resolvers:
            #         implicit_resolvers[key] = cls.yaml_implicit_resolvers[key][:]
            #     cls.yaml_implicit_resolvers = implicit_resolvers
            if first == null:
                first = []
            for ch in first:
                yaml_implicit_resolvers.get_or_add(ch, []).append([tag, regexp])

        # static func add_path_resolver(tag, path, kind=null):
        #     # Note: `add_path_resolver` is experimental.  The API could be changed.
        #     # `new_path` is a pattern that is matched against the path from the
        #     # root to the node that is being considered.  `node_path` elements are
        #     # tuples `(node_check, index_check)`.  `node_check` is a node class:
        #     # `ScalarNode`, `SequenceNode`, `MappingNode` or `None`.  `None`
        #     # matches any kind of a node.  `index_check` could be `None`, a boolean
        #     # value, a string value, or a number.  `None` and `False` match against
        #     # any _value_ of sequence and mapping nodes.  `True` matches against
        #     # any _key_ of a mapping node.  A string `index_check` matches against
        #     # a mapping value that corresponds to a scalar key which content is
        #     # equal to the `index_check` value.  An integer `index_check` matches
        #     # against a sequence value with the index equal to `index_check`.
        #     if not 'yaml_path_resolvers' in cls.__dict__:
        #         cls.yaml_path_resolvers = cls.yaml_path_resolvers.copy()
        #     new_path = []
        #     for element in path:
        #         if isinstance(element, (list, tuple)):
        #             if len(element) == 2:
        #                 node_check, index_check = element
        #             elif len(element) == 1:
        #                 node_check = element[0]
        #                 index_check = True
        #             else:
        #                 raise ResolverError("Invalid path element: %s" % element)
        #         else:
        #             node_check = null
        #             index_check = element
        #         if node_check is str:
        #             node_check = ScalarNode
        #         elif node_check is list:
        #             node_check = SequenceNode
        #         elif node_check is dict:
        #             node_check = MappingNode
        #         elif node_check not in [ScalarNode, SequenceNode, MappingNode]  \
        #                 and not isinstance(node_check, str) \
        #                 and node_check != null:
        #             raise ResolverError("Invalid node checker: %s" % node_check)
        #         if not isinstance(index_check, (str, int))  \
        #                 and index_check != null:
        #             raise ResolverError("Invalid index checker: %s" % index_check)
        #         new_path.append((node_check, index_check))
        #     if kind is str:
        #         kind = ScalarNode
        #     elif kind is list:
        #         kind = SequenceNode
        #     elif kind is dict:
        #         kind = MappingNode
        #     elif kind not in [ScalarNode, SequenceNode, MappingNode]    \
        #             and kind != null:
        #         raise ResolverError("Invalid node kind: %s" % kind)
        #     cls.yaml_path_resolvers[tuple(new_path), kind] = tag

        static func descend_resolver(current_node, current_index):
            if yaml_path_resolvers.is_empty():
                return
            var exact_paths = {}
            var prefix_paths = []
            if current_node != null:
                var depth = len(resolver_prefix_paths)
                for temp_array in resolver_prefix_paths[-1]:
                    var path = temp_array[0]
                    var kind = temp_array[1]
                    if check_resolver_prefix(depth, path, kind,
                            current_node, current_index):
                        if len(path) > depth:
                            prefix_paths.append([path, kind])
                        else:
                            var key = "%s\u001f%s" % [path, kind]
                            exact_paths[kind] = yaml_path_resolvers[key]
            else:
                for key in yaml_path_resolvers:
                    var path = key.get_slice('\u001f', 0)
                    var kind = key.get_slice('\u001f', 1)
                    if path.is_empty():
                        exact_paths[kind] = yaml_path_resolvers[key]
                    else:
                        prefix_paths.append([path, kind])
            resolver_exact_paths.append(exact_paths)
            resolver_prefix_paths.append(prefix_paths)

        static func ascend_resolver():
            if yaml_path_resolvers.is_empty():
                return
            resolver_exact_paths.pop_back()
            resolver_prefix_paths.pop_back()

        static func check_resolver_prefix(depth, path, kind,
                current_node, current_index):
            var temp_array = path[depth-1]
            var node_check = temp_array[0]
            var index_check = temp_array[1]
            if type_string(typeof(node_check)) == "String": 
                # Normally node_check shoule be a String, such as 'tag:yaml.org,2002:str'
                if current_node.tag != node_check:
                    return
            elif node_check != null:
                assert(false, "This should not happend, pls report")
            #     if not isinstance(current_node, node_check):
            #         return
            if index_check == true and current_index != null:
                return
            if (index_check == false or index_check == null)    \
                    and current_index == null:
                return
            if type_string(typeof(index_check)) == "String":
                if not (current_index.type == "SCALAR"
                        and index_check == current_index.value):
                    return
            elif type_string(typeof(index_check)) == "int" and not type_string(typeof(index_check)) == "bool":
                if index_check != current_index:
                    return
            return true

        static func resolve(kind, value, implicit):
            if kind == "SCALAR" and implicit[0]:
                var resolvers
                if value == '':
                    resolvers = yaml_implicit_resolvers.get('', [])
                else:
                    resolvers = yaml_implicit_resolvers.get(value[0], [])
                var wildcard_resolvers = yaml_implicit_resolvers.get(null, [])
                for temp_array in resolvers + wildcard_resolvers:
                    var tag = temp_array[0]
                    var regexp = temp_array[1]
                    if regexp.search(value) != null:
                        return tag
                implicit = implicit[1]
            if yaml_path_resolvers:
                var exact_paths = resolver_exact_paths[-1]
                if kind in exact_paths:
                    return exact_paths[kind]
                if null in exact_paths:
                    return exact_paths[null]
            if kind == "SCALAR":
                return DEFAULT_SCALAR_TAG
            elif kind == "SEQUENCE":
                return DEFAULT_SEQUENCE_TAG
            elif kind == "MAPPING":
                return DEFAULT_MAPPING_TAG

    class Constructor:

        static var yaml_constructors = {}
        static var yaml_multi_constructors = {}

        var constructed_objects = {}
        var recursive_objects = {}
        # var state_generators = []
        var deep_construct = false

        var composer :Composer

        func _init(p_composer):
            composer = p_composer

        static func init_yaml_constructors():
            Constructor.add_constructor(
                    'tag:yaml.org,2002:null',
                    Constructor.construct_yaml_null)

            Constructor.add_constructor(
                    'tag:yaml.org,2002:bool',
                    Constructor.construct_yaml_bool)

            Constructor.add_constructor(
                    'tag:yaml.org,2002:int',
                    Constructor.construct_yaml_int)

            Constructor.add_constructor(
                    'tag:yaml.org,2002:float',
                    Constructor.construct_yaml_float)

            # Constructor.add_constructor(
            #         'tag:yaml.org,2002:binary',
            #         Constructor.construct_yaml_binary)

            # Constructor.add_constructor(
            #         'tag:yaml.org,2002:timestamp',
            #         Constructor.construct_yaml_timestamp)

            # Constructor.add_constructor(
            #         'tag:yaml.org,2002:omap',
            #         Constructor.construct_yaml_omap)

            # Constructor.add_constructor(
            #         'tag:yaml.org,2002:pairs',
            #         Constructor.construct_yaml_pairs)

            # Constructor.add_constructor(
            #         'tag:yaml.org,2002:set',
            #         Constructor.construct_yaml_set)

            # Constructor.add_constructor(
            #         'tag:yaml.org,2002:str',
            #         Constructor.construct_yaml_str)

            # Constructor.add_constructor(
            #         'tag:yaml.org,2002:seq',
            #         Constructor.construct_yaml_seq)

            # Constructor.add_constructor(
            #         'tag:yaml.org,2002:map',
            #         Constructor.construct_yaml_map)

            # Constructor.add_constructor(null,
            #         Constructor.construct_undefined)

        func check_data():
            # If there are more documents available?
            return composer.check_node()

        # # NOTE: It is currently unclear whether GDScript has any unavailable keys.
        # func get_state_keys_blacklist():
        #     return []

        # var state_keys_blacklist_regexp
        # func get_state_keys_blacklist_regexp():
        #     if state_keys_blacklist_regexp == null:
        #         state_keys_blacklist_regexp = RegEx.create_from_string('(' + '|'.join(get_state_keys_blacklist()) + ')')
        #     return state_keys_blacklist_regexp

        # func check_state_key(key):
        #     # """Block special attributes/methods from being set in a newly created
        #     # object, to prevent user-controlled methods from being called during
        #     # deserialization"""
        #     if get_state_keys_blacklist_regexp().search(key) != null:
        #         SGYPaser.error("blacklisted key '%s' in instance state found" % key)

        func get_data():
            # Construct and return the next document.
            if composer.check_node():
                return construct_document(composer.get_node())

        func get_single_data():
            # Ensure that the stream contains a single document and construct it.
            var node = composer.get_single_node()
            if node != null:
                return construct_document(node)
            return null

        func construct_document(node):
            var data = construct_object(node)
            # while state_generators:
            #     state_generators = state_generators
            #     state_generators = []
            #     for generator in state_generators:
            #         for dummy in generator:
            #             pass
            constructed_objects = {}
            recursive_objects = {}
            deep_construct = false
            return data

        func construct_object(node, deep=false):
            var old_deep
            if node in constructed_objects:
                return constructed_objects[node]
            if deep:
                old_deep = deep_construct
                deep_construct = true
            if node in recursive_objects:
                SGYPaser.error("found unconstructable recursive node", node.start_mark)
            recursive_objects[node] = null
            var constructor = null
            var tag_suffix = null
            if node.tag in yaml_constructors:
                constructor = yaml_constructors[node.tag]
            else:
                var break_flag = false
                for tag_prefix in yaml_multi_constructors:
                    if tag_prefix != null and node.tag.begins_with(tag_prefix):
                        tag_suffix = node.tag.substr(len(tag_prefix))
                        constructor = yaml_multi_constructors[tag_prefix]
                        break_flag = true
                        break
                if break_flag == false:
                    if null in yaml_multi_constructors:
                        tag_suffix = node.tag
                        constructor = yaml_multi_constructors[null]
                    elif null in yaml_constructors:
                        constructor = yaml_constructors[null]
                    elif node.type == "SCALAR":
                        constructor = construct_scalar
                    elif node.type == "SEQUENCE":
                        constructor = construct_sequence
                    elif node.type == "MAPPING":
                        constructor = construct_mapping
            var data
            if tag_suffix == null:
                data = constructor.call(node)
            else:
                data = constructor.call(tag_suffix, node)
            # if isinstance(data, types.GeneratorType):
            #     generator = data
            #     data = next(generator)
            #     if deep_construct:
            #         for dummy in generator:
            #             pass
            #     else:
            #         state_generators.append(generator)
            constructed_objects[node] = data
            recursive_objects.erase(node)
            if deep:
                deep_construct = old_deep
            return data

        static func construct_scalar(node):
            if node.type != "SCALAR":
                SGYPaser.error("expected a scalar node, but found %s" % node.type,
                        node.start_mark)
            return node.value

        func construct_sequence(node, deep=false):
            if node.type != "SEQUENCE":
                SGYPaser.error("expected a sequence node, but found %s" % node.type,
                        node.start_mark)

            var result_array = []
            for child in node.value:
                result_array.append(construct_object(child, deep))
            return result_array

        func construct_mapping(node, deep=false):
            if node.type == "MAPPING":
                flatten_mapping(node)

            if node.type != "MAPPING":
                SGYPaser.error("expected a mapping node, but found %s" % node.type,
                        node.start_mark)
            var mapping = {}
            for temp_array in node.value:
                var key_node = temp_array[0]
                var value_node = temp_array[1]
                var key = construct_object(key_node, deep)
                # if not isinstance(key, collections.abc.Hashable):
                #     SGYPaser.error("while constructing a mapping", node.start_mark,
                #             "found unhashable key", key_node.start_mark)
                var value = construct_object(value_node, deep)
                mapping[key] = value
            return mapping

        func construct_pairs(node, deep=false):
            if node.type != "MAPPING":
                SGYPaser.error("expected a mapping node, but found %s" % node.type,
                        node.start_mark)
            var pairs = []
            for temp_array in node.value:
                var key_node = temp_array[0]
                var value_node = temp_array[1]
                var key = construct_object(key_node, deep)
                var value = construct_object(value_node, deep)
                pairs.append([key, value])
            return pairs

        static func add_constructor(tag :String, constructor :Callable):
            yaml_constructors[tag] = constructor

        static func add_multi_constructor(tag_prefix, multi_constructor):
            yaml_multi_constructors[tag_prefix] = multi_constructor

        func flatten_mapping(node):
            var merge = []
            var index = 0
            while index < len(node.value):
                var temp_array = node.value[index]
                var key_node = temp_array[0]
                var value_node = temp_array[1]
                if key_node.tag == 'tag:yaml.org,2002:merge':
                    node.value.erase(index)
                    if value_node.type == "MAPPING":
                        flatten_mapping(value_node)
                        merge.extend(value_node.value)
                    elif value_node.type == "SEQUENCE":
                        var submerge = []
                        for subnode in value_node.value:
                            if subnode.type != "MAPPING":
                                SGYPaser.error("while constructing a mapping",
                                        node.start_mark,
                                        "expected a mapping for merging, but found %s"
                                        % subnode.id, subnode.start_mark)
                            flatten_mapping(subnode)
                            submerge.append(subnode.value)
                        submerge.reverse()
                        for value in submerge:
                            merge.extend(value)
                    else:
                        SGYPaser.error("while constructing a mapping", node.start_mark,
                                "expected a mapping or list of mappings for merging, but found %s"
                                % value_node.id, value_node.start_mark)
                elif key_node.tag == 'tag:yaml.org,2002:value':
                    key_node.tag = 'tag:yaml.org,2002:str'
                    index += 1
                else:
                    index += 1
            if merge:
                node.value = merge + node.value

        static func construct_yaml_null(node):
            construct_scalar(node)
            return null

        const bool_values = {
            'yes':      true,
            'no':       false,
            'true':     true,
            'false':    false,
            'on':       true,
            'off':      false,
        }

        static func construct_yaml_bool(node):
            var value = construct_scalar(node)
            return bool_values[value.to_lower()]

        static func construct_yaml_int(node):
            var value = construct_scalar(node)
            value = value.replace('_', '')
            var sign = +1
            if value[0] == '-':
                sign = -1
            if value[0] in '+-':
                value = value.substr(1)
            if value == '0':
                return 0
            elif value.begins_with('0b'):
                return sign*value.substr(2).bin_to_int()
            elif value.begins_with('0x'):
                return sign*value.substr(2).hex_to_int()
            # FIXME
            # elif value[0] == '0':
            #     return sign*int(value, 8)
            elif ':' in value:
                var digits = []
                for part in value.split(':'):
                    digits.append(int(part)) 
                digits.reverse()
                var base = 1
                value = 0
                for digit in digits:
                    value += digit*base
                    base *= 60
                return sign*value
            else:
                return sign*int(value)

        static func construct_yaml_float(node):
            var value = construct_scalar(node)
            value = value.replace('_', '').to_lower()
            var sign = +1
            if value[0] == '-':
                sign = -1
            if value[0] in '+-':
                value = value.substr(1)
            if value == '.inf':
                return INF
            elif value == '.nan':
                return NAN
            elif ':' in value:
                var digits = []
                for part in value.split(':'):
                    digits.append(int(part)) 
                digits.reverse()
                var base = 1
                value = 0.0
                for digit in digits:
                    value += digit*base
                    base *= 60
                return sign*value
            else:
                return sign*float(value)

        # func construct_yaml_binary(node):
        #     try:
        #         value = construct_scalar(node).encode('ascii')
        #     except UnicodeEncodeError as exc:
        #         SGYPaser.error(None, None,
        #                 "failed to convert base64 data into ascii: %s" % exc,
        #                 node.start_mark)
        #     try:
        #         if hasattr(base64, 'decodebytes'):
        #             return base64.decodebytes(value)
        #         else:
        #             return base64.decodestring(value)
        #     except binascii.Error as exc:
        #         SGYPaser.error(None, None,
        #                 "failed to decode base64 data: %s" % exc, node.start_mark)

        # static var timestamp_regexp = RegEx.create_from_string(
        #         r'''(?x)^(?P<year>[0-9][0-9][0-9][0-9])
        #             -(?P<month>[0-9][0-9]?)
        #             -(?P<day>[0-9][0-9]?)
        #             (?:(?:[Tt]|[ \t]+)
        #             (?P<hour>[0-9][0-9]?)
        #             :(?P<minute>[0-9][0-9])
        #             :(?P<second>[0-9][0-9])
        #             (?:\.(?P<fraction>[0-9]*))?
        #             (?:[ \t]*(?P<tz>Z|(?P<tz_sign>[-+])(?P<tz_hour>[0-9][0-9]?)
        #             (?::(?P<tz_minute>[0-9][0-9]))?))?)?$''')

        # func construct_yaml_timestamp(node):
        #     value = construct_scalar(node)
        #     var match = timestamp_regexp.search_all(node.value)
        #     values = match.strings
        #     year = int(values['year'])
        #     month = int(values['month'])
        #     day = int(values['day'])
        #     if not values['hour']:
        #         return datetime.date(year, month, day)
        #     hour = int(values['hour'])
        #     minute = int(values['minute'])
        #     second = int(values['second'])
        #     fraction = 0
        #     tzinfo = null
        #     if values['fraction']:
        #         fraction = values['fraction'].substr(0,6)
        #         while len(fraction) < 6:
        #             fraction += '0'
        #         fraction = int(fraction)
        #     if values['tz_sign']:
        #         tz_hour = int(values['tz_hour'])
        #         tz_minute = int(values['tz_minute'] or 0)
        #         delta = datetime.timedelta(hours=tz_hour, minutes=tz_minute)
        #         if values['tz_sign'] == '-':
        #             delta = -delta
        #         tzinfo = datetime.timezone(delta)
        #     elif values['tz']:
        #         tzinfo = datetime.timezone.utc
        #     return datetime.datetime(year, month, day, hour, minute, second, fraction,
        #                             tzinfo=tzinfo)

        # func construct_yaml_omap(node):
        #     # Note: we do not check for duplicate keys, because it's too
        #     # CPU-expensive.
        #     omap = []
        #     yield omap
        #     if not isinstance(node, SequenceNode):
        #         SGYPaser.error("while constructing an ordered map", node.start_mark,
        #                 "expected a sequence, but found %s" % node.id, node.start_mark)
        #     for subnode in node.value:
        #         if not isinstance(subnode, MappingNode):
        #             SGYPaser.error("while constructing an ordered map", node.start_mark,
        #                     "expected a mapping of length 1, but found %s" % subnode.id,
        #                     subnode.start_mark)
        #         if len(subnode.value) != 1:
        #             SGYPaser.error("while constructing an ordered map", node.start_mark,
        #                     "expected a single mapping item, but found %d items" % len(subnode.value),
        #                     subnode.start_mark)
        #         key_node, value_node = subnode.value[0]
        #         key = construct_object(key_node)
        #         value = construct_object(value_node)
        #         omap.append((key, value))

        # func construct_yaml_pairs(node):
        #     # Note: the same code as `construct_yaml_omap`.
        #     pairs = []
        #     yield pairs
        #     if not isinstance(node, SequenceNode):
        #         SGYPaser.error("while constructing pairs", node.start_mark,
        #                 "expected a sequence, but found %s" % node.id, node.start_mark)
        #     for subnode in node.value:
        #         if not isinstance(subnode, MappingNode):
        #             SGYPaser.error("while constructing pairs", node.start_mark,
        #                     "expected a mapping of length 1, but found %s" % subnode.id,
        #                     subnode.start_mark)
        #         if len(subnode.value) != 1:
        #             SGYPaser.error("while constructing pairs", node.start_mark,
        #                     "expected a single mapping item, but found %d items" % len(subnode.value),
        #                     subnode.start_mark)
        #         key_node, value_node = subnode.value[0]
        #         key = construct_object(key_node)
        #         value = construct_object(value_node)
        #         pairs.append((key, value))

        # func construct_yaml_set(node):
        #     data = set()
        #     yield data
        #     value = construct_mapping(node)
        #     data.update(value)

        # static func construct_yaml_str(node):
        #     return construct_scalar(node)

        # func construct_yaml_seq(node):
        #     data = []
        #     yield data
        #     data.extend(construct_sequence(node))

        # func construct_yaml_map(node):
        #     data = {}
        #     yield data
        #     value = construct_mapping(node)
        #     data.update(value)

        # func construct_yaml_object(node, cls):
        #     data = cls.__new__(cls)
        #     yield data
        #     if hasattr(data, '__setstate__'):
        #         state = construct_mapping(node, deep=true)
        #         data.__setstate__(state)
        #     else:
        #         state = construct_mapping(node)
        #         data.__dict__.update(state)

        # static func construct_undefined(node):
        #     SGYPaser.error("could not determine a constructor for the tag %s" % node.tag,
        #             node.start_mark)


    # Dump Part

    class Representer:

        static var yaml_representers = {}
        static var yaml_multi_representers = {}
        
        static var represented_objects = {}
        static var object_keeper = []
        static var alias_key = null

        static var default_style
        static var default_flow_style :bool
        static var sort_keys          :bool

        func _init(p_default_style=null, p_default_flow_style=false, p_sort_keys=true):
            default_style       = p_default_style
            default_flow_style  = p_default_flow_style
            sort_keys           = p_sort_keys

        static func init_yaml_representers():
            Representer.add_representer("Nil",
                    Representer.represent_null)

            Representer.add_representer("String",
                    Representer.represent_str)

            # Representer.add_representer(bytes,
            #         Representer.represent_binary)

            Representer.add_representer("bool",
                    Representer.represent_bool)

            Representer.add_representer("int",
                    Representer.represent_int)

            Representer.add_representer("float",
                    Representer.represent_float)

            Representer.add_representer("Array",
                    Representer.represent_array)

            # Representer.add_representer(tuple,
            #         Representer.represent_list)

            Representer.add_representer("Dictionary",
                    Representer.represent_dict)

            # Representer.add_representer(set,
            #         Representer.represent_set)

            # Representer.add_representer(datetime.date,
            #         Representer.represent_date)

            # Representer.add_representer(datetime.datetime,
            #         Representer.represent_datetime)

            Representer.add_representer(null,
                    Representer.represent_undefined)


        static func represent(data):
            var node = represent_data(data)
            Serializer.serialize(node)
            represented_objects = {}
            object_keeper = []
            alias_key = null

        static func represent_data(data):
            if ignore_aliases(data):
                alias_key = null
            else:
                alias_key = data.get_instance_id()
            if alias_key != null:
                if alias_key in represented_objects:
                    var node = represented_objects[alias_key]
                    return node
                object_keeper.append(data)

            var node
            var data_type = type_string(typeof(data)) if type_string(typeof(data)) != "Object" else data.get_class()
            if data_type in yaml_representers:
                node = yaml_representers[data_type].call(data)
            elif null in yaml_multi_representers:
                node = yaml_multi_representers[null].call(data)
            elif null in yaml_representers:
                node = yaml_representers[null].call(data)
            else:
                node = YAMLNode.new("SCALAR", null, str(data))
            return node

        static func add_representer(data_type, representer):
            yaml_representers[data_type] = representer

        static func add_multi_representer(data_type, representer):
            yaml_multi_representers[data_type] = representer

        static func represent_scalar(tag, value, style=null):
            if style == null:
                style = default_style
            var node = YAMLNode.new("SCALAR", tag, value, style)
            if alias_key != null:
                represented_objects[alias_key] = node
            return node

        static func represent_sequence(tag, sequence, p_flow_style=null):
            var value = []
            var node = YAMLNode.new("SEQUENCE", tag, value, false)
            if alias_key != null:
                represented_objects[alias_key] = node
            var best_style = true
            for item in sequence:
                var node_item :YAMLNode = represent_data(item)
                if not (node_item.type == "SCALAR" and node_item.style == null):
                    best_style = false
                value.append(node_item)
            if p_flow_style == null:
                if default_flow_style != null:
                    node.is_flow_style = default_flow_style
                else:
                    node.is_flow_style = best_style
            else:
                node.is_flow_style = p_flow_style
                
            return node

        static func represent_mapping(tag, mapping, p_flow_style=null):
            var value = []
            var node = YAMLNode.new("MAPPING", tag, value, false)
            if alias_key != null:
                represented_objects[alias_key] = node
            var best_style = true
            # if hasattr(mapping, 'items'):
            #     mapping = list(mapping.items())
            #     if sort_keys:
            #         # try:
            #         mapping = sorted(mapping)
            #         # except TypeError:
            #         #     pass

            if sort_keys:
                mapping.sort()

            # for temp_array in mapping:
            #     var item_key = temp_array[0]
            #     var item_value = temp_array[1]
            #     var node_key = represent_data(item_key)
            #     var node_value = represent_data(item_value)
            #     if not (node_key.type   == "SCALAR"  and not node_key.style):
            #         best_style = false
            #     if not (node_value.type == "SCALAR"  and not node_value.style):
            #         best_style = false
            #     value.append([node_key, node_value])
            
            for key in mapping:
                var mapping_value = mapping[key]
                var node_key = represent_data(key)
                var node_value = represent_data(mapping_value)
                if not (node_key.type   == "SCALAR"  and not node_key.style):
                    best_style = false
                if not (node_value.type == "SCALAR"  and not node_value.style):
                    best_style = false
                value.append([node_key, node_value])

            if p_flow_style == null:
                if default_flow_style != null:
                    node.is_flow_style = default_flow_style
                else:
                    node.is_flow_style = best_style
            else:
                node.is_flow_style = p_flow_style

            return node

        static func ignore_aliases(data):
            if type_string(typeof(data)) == "Object":
                return false
            return true


        static func represent_null(data):
            return represent_scalar('tag:yaml.org,2002:null', 'null')

        static func represent_str(data :String):
            return represent_scalar('tag:yaml.org,2002:str', data)

        # func represent_binary(data):
        #     if hasattr(base64, 'encodebytes'):
        #         data = base64.encodebytes(data).decode('ascii')
        #     else:
        #         data = base64.encodestring(data).decode('ascii')
        #     return represent_scalar('tag:yaml.org,2002:binary', data, style='|')

        static func represent_bool(data :bool):
            var value = 'true' if data else 'false'
            return represent_scalar('tag:yaml.org,2002:bool', value)

        static func represent_int(data :int):
            return represent_scalar('tag:yaml.org,2002:int', str(data))

        static func represent_float(data :float):
            var value
            if data == NAN:
                value = '.nan'
            elif data == INF:
                value = '.inf'
            elif data == -INF:
                value = '-.inf'
            else:
                value = str(data).to_lower()
            return represent_scalar('tag:yaml.org,2002:float', value)

        static func represent_array(data):
            return represent_sequence('tag:yaml.org,2002:seq', data)

        static func represent_dict(data):
            return represent_mapping('tag:yaml.org,2002:map', data)

        static func represent_undefined(data):
            SGYPaser.error("cannot represent an object", data)

    class Serializer:
        const ANCHOR_TEMPLATE = 'id%03d'

        static var use_encoding
        static var use_explicit_start = false
        static var use_explicit_end   = false
        static var use_version
        static var use_tags
        static var serialized_nodes = {}
        static var anchors          = {}
        static var last_anchor_id   = 0
        static var closed           = null

        static func set_up(encoding=null,
                explicit_start=false, explicit_end=false, version=null, tags=null):
            use_encoding       = encoding
            use_explicit_start = explicit_start
            use_explicit_end   = explicit_end
            use_version        = version
            use_tags           = tags

        static func open():
            if closed == null:
                Emitter.emit(Event.new("STREAM_START"))
                closed = false
            elif closed:
                SGYPaser.error("serializer is closed")
            else:
                SGYPaser.error("serializer is already opened")

        static func close():
            if closed == null:
                SGYPaser.error("serializer is not opened")
            elif not closed:
                Emitter.emit(Event.new("STREAM_END"))
                closed = true

        static func serialize(node):
            if closed == null:
                SGYPaser.error("serializer is not opened")
            elif closed:
                SGYPaser.error("serializer is closed")
            Emitter.emit(Event.new("DOCUMENT_START", use_explicit_start,
                use_version, use_tags))
            anchor_node(node)
            serialize_node(node, null, null)
            Emitter.emit(Event.new("DOCUMENT_END", use_explicit_end))
            serialized_nodes = {}
            anchors = {}
            last_anchor_id = 0

        static func anchor_node(node):
            if node in anchors:
                if anchors[node] == null:
                    anchors[node] = generate_anchor(node)
            else:
                anchors[node] = null
                if node.type == "SEQUENCE":
                    for item in node.value:
                        anchor_node(item)
                elif node.type == "MAPPING":
                    for temp_array in node.value:
                        var key = temp_array[0]
                        var value = temp_array[1]
                        anchor_node(key)
                        anchor_node(value)

        static func generate_anchor(node):
            last_anchor_id += 1
            return ANCHOR_TEMPLATE % last_anchor_id

        static func serialize_node(node, parent, index):
            var alias = anchors[node]
            if node in serialized_nodes:
                Emitter.emit(Event.new("ALIAS", alias))
            else:
                serialized_nodes[node] = true
                Resolver.descend_resolver(parent, index)
                if node.type == "SCALAR":
                    var detected_tag = Resolver.resolve("SCALAR", node.value, [true, false])
                    var default_tag = Resolver.resolve("SCALAR", node.value, [false, true])
                    var implicit = [(node.tag == detected_tag), (node.tag == default_tag)]
                    Emitter.emit(Event.new("SCALAR", alias, node.tag, implicit, node.value,
                        node.style))
                elif node.type == "SEQUENCE":
                    var implicit = (node.tag
                                == Resolver.resolve("SEQUENCE", node.value, true))
                    Emitter.emit(Event.new("SEQUENCE_START", alias, node.tag, implicit,
                        node.is_flow_style))
                    index = 0
                    for item in node.value:
                        serialize_node(item, node, index)
                        index += 1
                    Emitter.emit(Event.new("SEQUENCE_END"))
                elif node.type == "MAPPING":
                    var implicit = (node.tag
                                == Resolver.resolve("MAPPING", node.value, true))
                    Emitter.emit(Event.new("MAPPING_START", alias, node.tag, implicit,
                        node.is_flow_style))
                    for temp_array in node.value:
                        var key = temp_array[0]
                        var value = temp_array[1]
                        serialize_node(key, node, null)
                        serialize_node(value, node, key)
                    Emitter.emit(Event.new("MAPPING_END"))
                Resolver.ascend_resolver()

    class Emitter:
        # Emitter expects events obeying the following grammar:
        # stream ::= STREAM-START document* STREAM-END
        # document ::= DOCUMENT-START node DOCUMENT-END
        # node ::= SCALAR | sequence | mapping
        # sequence ::= SEQUENCE-START node* SEQUENCE-END
        # mapping ::= MAPPING-START (node node)* MAPPING-END


        const DEFAULT_TAG_PREFIXES = {
            '!' : '!',
            'tag:yaml.org,2002:' : '!!',
        }


        # The stream should have the methods `write` and possibly `flush`.
        static var stream

        # Encoding can be overridden by STREAM-START.
        static var encoding = null

        # Emitter is a state machine with a stack of states to handle nested
        # structures.
        static var states = []
        static var state : Callable = expect_stream_start

        # Current event and the event queue.
        static var events = []
        static var event = null

        # The current indentation level and the stack of previous indents.
        static var indents = []
        static var indent = null

        # Flow level.
        static var flow_level = 0

        # Contexts.
        static var root_context = false
        static var sequence_context = false
        static var mapping_context = false
        static var simple_key_context = false

        # Characteristics of the last emitted character:
        #  - current position.
        #  - is it a whitespace?
        #  - is it an indention character
        #    (indentation space, '-', '?', or ':')?
        static var line = 0
        static var column = 0
        static var whitespace = true
        static var indention = true

        # Whether the document requires an explicit document indicator
        static var open_ended = false

        # Formatting details.
        static var canonical
        static var allow_unicode
        static var best_indent = 2
        static var best_width = 80
        static var best_line_break = '\n'


        # Tag prefixes.
        static var tag_prefixes = null

        # Prepared anchor and tag.
        static var prepared_anchor = null
        static var prepared_tag = null

        # Scalar analysis and style.
        static var analysis = null
        static var style = null

        static func set_up(p_canonical=null, p_allow_unicode=null, indent=2, width=80, line_break='\n'):
            canonical = p_canonical
            allow_unicode = p_allow_unicode

            if 1 < indent and indent < 10:
                best_indent = indent
            if width > best_indent*2:
                best_width = width
            if line_break in ['\r', '\n', '\r\n']:
                best_line_break = line_break

        static func emit(new_event:Event):
            print(new_event.type)
            events.append(new_event)
            while not need_more_events():
                event = events.pop_front()
                state.call()
                event = null

        # In some cases, we wait for a few next events before emitting.

        static func need_more_events():
            if events.is_empty():
                return true
            event = events[0]
            if event.type == "DOCUMENT_START":
                return need_events(1)
            elif event.type == "SEQUENCE_START":
                return need_events(2)
            elif event.type == "MAPPING_START":
                return need_events(3)
            else:
                return false

        static func need_events(count):
            var level = 0
            for event in events.slice(1, events.size()):
                if event.type in ["DOCUMENT_START", "SEQUENCE_START", "MAPPING_START"]:
                    level += 1
                elif event.type in ["DOCUMENT_END", "SEQUENCE_END", "MAPPING_END"]:
                    level -= 1
                elif event.type == "STREAM_END":
                    level = -1
                if level < 0:
                    return false
            return (len(events) < count+1)

        static func increase_indent(flow=false, indentless=false):
            indents.append(indent)
            if indent == null:
                if flow:
                    indent = best_indent
                else:
                    indent = 0
            elif not indentless:
                indent += best_indent

        # States.

        # Stream handlers.

        static func expect_stream_start():
            if event.type == "STREAM_START":
                #FIXME
                # if event.encoding != null:
                #     encoding = event.encoding
                write_stream_start()
                state = expect_first_document_start
            else:
                SGYPaser.error("expected StreamStartEvent, but got %s"
                        % event)

        static func expect_nothing():
            SGYPaser.error("expected nothing, but got %s" % event)


        # Document handlers.

        static func expect_first_document_start():
            return expect_document_start(true)

        static func expect_document_start(is_first_document=false):
            if event.type == "DOCUMENT_START":
                if (event.yaml_version or event.tags) and open_ended:
                    write_indicator('...', true)
                    write_indent()
                if event.yaml_version != null:
                    var version_text = prepare_version(event.yaml_version)
                    write_version_directive(version_text)
                tag_prefixes = DEFAULT_TAG_PREFIXES.duplicate()
                if event.tags:
                    var handles = event.tags.keys()
                    handles.sort()
                    for handle in handles:
                        var prefix = event.tags[handle]
                        tag_prefixes[prefix] = handle
                        var handle_text = prepare_tag_handle(handle)
                        var prefix_text = prepare_tag_prefix(prefix)
                        write_tag_directive(handle_text, prefix_text)
                var implicit = (is_first_document and not event.is_explicit and not canonical
                        and not event.yaml_version and not event.tags
                        and not check_empty_document())
                if not implicit:
                    write_indent()
                    write_indicator('---', true)
                    if canonical:
                        write_indent()
                state = expect_document_root
            elif event.type == "STREAM_END":
                if open_ended:
                    write_indicator('...', true)
                    write_indent()
                write_stream_end()
                state = expect_nothing
            else:
                SGYPaser.error("expected DocumentStartEvent, but got %s"
                        % event)

        static func expect_document_end():
            if event.type == "DOCUMENT_END":
                write_indent()
                if event.is_explicit:
                    write_indicator('...', true)
                    write_indent()
                flush_stream()
                state = expect_document_start
            else:
                SGYPaser.error("expected DocumentEndEvent, but got %s"
                        % event)

        static func expect_document_root():
            states.append(expect_document_end)
            expect_node(ExpectNodeType.ROOT)

        # Node handlers.
        enum ExpectNodeType {ROOT, SEQUENCE, MAPPING}
        static func expect_node(type, simple_key=false):
            root_context        = (type == ExpectNodeType.ROOT)
            sequence_context    = (type == ExpectNodeType.SEQUENCE)
            mapping_context     = (type == ExpectNodeType.MAPPING)
            simple_key_context  = simple_key
            if event.type == "ALIAS":
                expect_alias()
            elif event.type in ["SCALAR", "SEQUENCE_START", "MAPPING_START"]:
                process_anchor('&')
                process_tag()
                if event.type == "SCALAR":
                    expect_scalar()
                elif event.type == "SEQUENCE_START":
                    if flow_level or canonical or event.is_flow_style   \
                            or check_empty_sequence():
                        expect_flow_sequence()
                    else:
                        expect_block_sequence()
                elif event.type == "MAPPING_START":
                    if flow_level or canonical or event.is_flow_style   \
                            or check_empty_mapping():
                        expect_flow_mapping()
                    else:
                        expect_block_mapping()
            else:
                SGYPaser.error("expected NodeEvent, but got %s" % event)

        static func expect_alias():
            if event.anchor == null:
                SGYPaser.error("anchor is not specified for alias")
            process_anchor('*')
            state = states.pop_back()

        static func expect_scalar():
            var flow = true
            increase_indent(flow)
            process_scalar()
            indent = indents.pop_back()
            state = states.pop_back()

        # Flow sequence handlers.

        static func expect_flow_sequence():
            var whitespace=true
            write_indicator('[', true, whitespace)
            flow_level += 1
            var flow = true
            increase_indent(flow)
            state = expect_first_flow_sequence_item

        static func expect_first_flow_sequence_item():
            if event.type == "SEQUENCE_END":
                indent = indents.pop_back()
                flow_level -= 1
                write_indicator(']', false)
                state = states.pop_back()
            else:
                if canonical or column > best_width:
                    write_indent()
                states.append(expect_flow_sequence_item)
                expect_node(ExpectNodeType.SEQUENCE)

        static func expect_flow_sequence_item():
            if event.type == "SEQUENCE_END":
                indent = indents.pop_back()
                flow_level -= 1
                if canonical:
                    write_indicator(',', false)
                    write_indent()
                write_indicator(']', false)
                state = states.pop_back()
            else:
                write_indicator(',', false)
                if canonical or column > best_width:
                    write_indent()
                states.append(expect_flow_sequence_item)
                expect_node(ExpectNodeType.SEQUENCE)

        # Flow mapping handlers.

        static func expect_flow_mapping():
            var whitespace=true
            write_indicator('{', true, whitespace)
            flow_level += 1
            var flow=true
            increase_indent(flow)
            state = expect_first_flow_mapping_key

        static func expect_first_flow_mapping_key():
            if event.type == "MAPPING_END":
                indent = indents.pop_back()
                flow_level -= 1
                write_indicator('}', false)
                state = states.pop_back()
            else:
                if canonical or column > best_width:
                    write_indent()
                if not canonical and check_simple_key():
                    states.append(expect_flow_mapping_simple_value)
                    expect_node(ExpectNodeType.MAPPING, true)
                else:
                    write_indicator('?', true)
                    states.append(expect_flow_mapping_value)
                    expect_node(ExpectNodeType.MAPPING)

        static func expect_flow_mapping_key():
            if event.type == "MAPPING_END":
                indent = indents.pop_back()
                flow_level -= 1
                if canonical:
                    write_indicator(',', false)
                    write_indent()
                write_indicator('}', false)
                state = states.pop_back()
            else:
                write_indicator(',', false)
                if canonical or column > best_width:
                    write_indent()
                if not canonical and check_simple_key():
                    states.append(expect_flow_mapping_simple_value)
                    expect_node(ExpectNodeType.MAPPING, true)
                else:
                    write_indicator('?', true)
                    states.append(expect_flow_mapping_value)
                    expect_node(ExpectNodeType.MAPPING)

        static func expect_flow_mapping_simple_value():
            write_indicator(':', false)
            states.append(expect_flow_mapping_key)
            expect_node(ExpectNodeType.MAPPING)

        static func expect_flow_mapping_value():
            if canonical or column > best_width:
                write_indent()
            write_indicator(':', true)
            states.append(expect_flow_mapping_key)
            expect_node(ExpectNodeType.MAPPING)

        # Block sequence handlers.

        static func expect_block_sequence():
            var indentless = (mapping_context and not indention)
            increase_indent(false, indentless)
            state = expect_first_block_sequence_item

        static func expect_first_block_sequence_item():
            return expect_block_sequence_item(true)

        static func expect_block_sequence_item(first=false):
            if not first and event.type == "SEQUENCE_END":
                indent = indents.pop_back()
                state = states.pop_back()
            else:
                write_indent()
                var indention=true
                write_indicator('-', true, false, indention)
                states.append(expect_block_sequence_item)
                expect_node(ExpectNodeType.SEQUENCE)

        # Block mapping handlers.

        static func expect_block_mapping():
            var flow=false
            increase_indent(flow)
            state = expect_first_block_mapping_key

        static func expect_first_block_mapping_key():
            return expect_block_mapping_key(true)

        static func expect_block_mapping_key(first=false):
            if not first and event.type == "MAPPING_END":
                indent = indents.pop_back()
                state = states.pop_back()
            else:
                write_indent()
                if check_simple_key():
                    states.append(expect_block_mapping_simple_value)
                    expect_node(ExpectNodeType.MAPPING, true)
                else:
                    var indention=true
                    write_indicator('?', true, false, indention)
                    states.append(expect_block_mapping_value)
                    expect_node(ExpectNodeType.MAPPING)

        static func expect_block_mapping_simple_value():
            write_indicator(':', false)
            states.append(expect_block_mapping_key)
            expect_node(ExpectNodeType.MAPPING)

        static func expect_block_mapping_value():
            write_indent()
            var indention=true
            write_indicator(':', true, false, indention)
            states.append(expect_block_mapping_key)
            expect_node(ExpectNodeType.MAPPING)

        # Checkers.

        static func check_empty_sequence():
            return (event.type == "SEQUENCE_START" and events.is_empty() == false
                    and events[0].type == "SEQUENCE_END")

        static func check_empty_mapping():
            return (event.type == "MAPPING_START" and events.is_empty() == false
                    and events[0].type == "MAPPING_END")

        static func check_empty_document():
            if not event.type == "DOCUMENT_START" or events.is_empty():
                return false
            event = events[0]
            return (event.type == "SCALAR" and event.anchor == null
                    and event.tag == null and event.implicit and event.value == '')

        static func check_simple_key():
            var length = 0
            if event.type in ["SEQUENCE_START", "MAPPING_START", "ALIAS", "SCALAR"] and event.anchor != null:
                if prepared_anchor == null:
                    prepared_anchor = prepare_anchor(event.anchor)
                length += len(prepared_anchor)
            if event.type in ["SCALAR", "SEQUENCE_START", "MAPPING_START"]  \
                    and event.tag != null:
                if prepared_tag == null:
                    prepared_tag = prepare_tag(event.tag)
                length += len(prepared_tag)
            if event.type == "SCALAR":
                if analysis == null:
                    analysis = analyze_scalar(event.value)
                length += len(analysis.scalar)
            return (length < 128 and (event.type == "ALIAS"
                or (event.type == "SCALAR"
                        and not analysis.empty and not analysis.multiline)
                or check_empty_sequence() or check_empty_mapping()))

        # Anchor, Tag, and Scalar processors.

        static func process_anchor(indicator):
            if event.anchor == null:
                prepared_anchor = null
                return
            if prepared_anchor == null:
                prepared_anchor = prepare_anchor(event.anchor)
            if prepared_anchor:
                write_indicator(indicator+prepared_anchor, true)
            prepared_anchor = null

        static func process_tag():
            var tag = event.tag
            if event.type == "SCALAR":
                if style == null:
                    style = choose_scalar_style()
                if ((not canonical or tag == null) and
                    ((style == '' and event.implicit[0])
                            or (style != '' and event.implicit[1]))):
                    prepared_tag = null
                    return
                if event.implicit[0] and tag == null:
                    tag = '!'
                    prepared_tag = null
            else:
                if (not canonical or tag == null) and event.implicit:
                    prepared_tag = null
                    return
            if tag == null:
                SGYPaser.error("tag is not specified")
            if prepared_tag == null:
                prepared_tag = prepare_tag(tag)
            if prepared_tag:
                write_indicator(prepared_tag, true)
            prepared_tag = null

        static func choose_scalar_style():
            if analysis == null:
                analysis = analyze_scalar(event.value)
            if event.style == '"' or canonical:
                return '"'
            if event.style == null and event.implicit[0]:
                if (not (simple_key_context and
                        (analysis.empty or analysis.multiline))
                    and (flow_level and analysis.allow_flow_plain
                        or (not flow_level and analysis.allow_block_plain))):
                    return ''
            if event.style and event.style in '|>':
                if (not flow_level and not simple_key_context
                        and analysis.allow_block):
                    return event.style
            if not event.style or event.style == '\'':
                if (analysis.allow_single_quoted and
                        not (simple_key_context and analysis.multiline)):
                    return '\''
            return '"'

        static func process_scalar():
            if analysis == null:
                analysis = analyze_scalar(event.value)
            if style == null:
                style = choose_scalar_style()
            var split = (not simple_key_context)
            #if analysis.multiline and split    \
            #        and (not style or style in '\'\"'):
            #    write_indent()
            if style == '"':
                write_double_quoted(analysis.scalar, split)
            elif style == '\'':
                write_single_quoted(analysis.scalar, split)
            elif style == '>':
                write_folded(analysis.scalar)
            elif style == '|':
                write_literal(analysis.scalar)
            else:
                write_plain(analysis.scalar, split)
            analysis = null
            style = null

        # Analyzers.

        static func prepare_version(version):
            var major = version[0]
            var minor = version[1]
            if major != 1:
                SGYPaser.error("unsupported YAML version: %d.%d" % [major, minor])
            return '%d.%d' % [major, minor]

        static func prepare_tag_handle(handle):
            if not handle:
                SGYPaser.error("tag handle must not be empty")
            if handle[0] != '!' or handle[-1] != '!':
                SGYPaser.error("tag handle must start and end with '!': %r" % handle)
            for ch in handle.substr(1, handle.size()-1):
                if not (('0' <= ch and ch <= '9') or ('A' <= ch and ch <= 'Z') or ('a' <= ch and ch <= 'z')    \
                        or ch in '-_'):
                    SGYPaser.error("invalid character %c in the tag handle: %s"
                            % [ch, handle])
            return handle

        static func prepare_tag_prefix(prefix):
            if prefix.is_empty():
                SGYPaser.error("tag prefix must not be empty")
            var chunks = []
            var start = 0
            var end = 0
            if prefix[0] == '!':
                end = 1
            while end < len(prefix):
                var ch = prefix[end]
                if ('0' <= ch and ch <= '9') or ('A' <= ch and ch <= 'Z') or ('a' <= ch and ch <= 'z') \
                        or ch in '-;/?!:@&=+$,_.~*\'()[]':
                    end += 1
                else:
                    if start < end:
                        chunks.append(prefix.substr(start, end-start))
                    start = end+1
                    end = end+1
                    var data = ch.encode('utf-8')
                    for c in data:
                        chunks.append('%%%02X' % ord(c))
            if start < end:
                chunks.append(prefix.substr(start, end-start))
            return ''.join(chunks)

        static func prepare_tag(tag):
            if tag.is_empty():
                SGYPaser.error("tag must not be empty")
            if tag == '!':
                return tag
            var handle = null
            var suffix = tag
            var prefixes = tag_prefixes.keys()
            prefixes.sort()
            for prefix in prefixes:
                if tag.begins_with(prefix)   \
                        and (prefix == '!' or len(prefix) < len(tag)):
                    handle = tag_prefixes[prefix]
                    suffix = tag.substr(len(prefix))
            var chunks = []
            var start = 0
            var end = 0
            while end < len(suffix):
                var ch = suffix[end]
                if ('0' <= ch and ch <= '9') or ('A' <= ch and ch <= 'Z') or ('a' <= ch and ch <= 'z') \
                        or ch in '-;/?:@&=+$,_.~*\'()[]'   \
                        or (ch == '!' and handle != '!'):
                    end += 1
                else:
                    if start < end:
                        chunks.append(suffix.substr(start, end-start))
                    start = end+1
                    end = end+1
                    var data = ch.encode('utf-8')
                    for c in data:
                        chunks.append('%%%02X' % c)
            if start < end:
                chunks.append(suffix.substr(start, end-start))
            var suffix_text = ''.join(chunks)
            if handle:
                return '%s%s' % [handle, suffix_text]
            else:
                return '!<%s>' % suffix_text

        static func prepare_anchor(anchor):
            if not anchor:
                SGYPaser.error("anchor must not be empty")
            for ch in anchor:
                if not (('0' <= ch and ch <= '9') or ('A' <= ch and ch <= 'Z') or ('a' <= ch and ch <= 'z')    \
                        or ch in '-_'):
                    SGYPaser.error("invalid character %c in the anchor: %s"
                            % [ch, anchor])
            return anchor

        static func analyze_scalar(scalar :String) -> Dictionary:

            # Empty scalar is a special case.
            if scalar.is_empty():
                return {
                        scalar=scalar, 
                        empty=true, 
                        multiline=false,
                        allow_flow_plain=false, 
                        allow_block_plain=true,
                        allow_single_quoted=true, 
                        allow_double_quoted=true,
                        allow_block=false
                    }

            # Indicators and special characters.
            var block_indicators = false
            var flow_indicators = false
            var line_breaks = false
            var special_characters = false

            # Important whitespace combinations.
            var leading_space = false
            var leading_break = false
            var trailing_space = false
            var trailing_break = false
            var break_space = false
            var space_break = false

            # Check document indicators.
            if scalar.begins_with('---') or scalar.begins_with('...'):
                block_indicators = true
                flow_indicators = true

            # First character or preceded by a whitespace.
            var preceded_by_whitespace = true

            # Last character or followed by a whitespace.
            var followed_by_whitespace = (len(scalar) == 1 or
                    scalar[1] in '\u0003 \t\r\n')

            # The previous character is a space.
            var previous_space = false

            # The previous character is a break.
            var previous_break = false

            var index = 0
            while index < len(scalar):
                var ch = scalar[index]

                # Check for indicators.
                if index == 0:
                    # Leading indicators are special characters.
                    if ch in '#,[]{}&*!|>\'\"%@`':
                        flow_indicators = true
                        block_indicators = true
                    if ch in '?:':
                        flow_indicators = true
                        if followed_by_whitespace:
                            block_indicators = true
                    if ch == '-' and followed_by_whitespace:
                        flow_indicators = true
                        block_indicators = true
                else:
                    # Some indicators cannot appear within a scalar as well.
                    if ch in ',?[]{}':
                        flow_indicators = true
                    if ch == ':':
                        flow_indicators = true
                        if followed_by_whitespace:
                            block_indicators = true
                    if ch == '#' and preceded_by_whitespace:
                        flow_indicators = true
                        block_indicators = true

                # Check for line breaks, special, and unicode characters.
                if ch in '\n':
                    line_breaks = true
                # if not (ch == '\n' or '\x20' <= ch <= '\x7E'):
                    # if (ch == '\x85' or '\xA0' <= ch <= '\uD7FF'
                    #         or '\uE000' <= ch <= '\uFFFD'
                    #         or '\U00010000' <= ch < '\U0010ffff') and ch != '\uFEFF':
                if not (ch == '\n' or ('\u0020' <= ch and ch <= '\u007E')):
                    if ((ord('\uE000') <= ord(ch) and ord(ch) <= ord('\uFFFD'))
                            or (ord('\U010000') <= ord(ch) and ord(ch) < ord('\U10ffff'))) and ch != '\uFEFF':
                        # unicode_characters = true
                        if not allow_unicode:
                            special_characters = true
                    else:
                        special_characters = true

                # Detect important whitespace combinations.
                if ch == ' ':
                    if index == 0:
                        leading_space = true
                    if index == len(scalar)-1:
                        trailing_space = true
                    if previous_break:
                        break_space = true
                    previous_space = true
                    previous_break = false
                elif ch in '\n':
                    if index == 0:
                        leading_break = true
                    if index == len(scalar)-1:
                        trailing_break = true
                    if previous_space:
                        space_break = true
                    previous_space = false
                    previous_break = true
                else:
                    previous_space = false
                    previous_break = false

                # Prepare for the next character.
                index += 1
                preceded_by_whitespace = (ch in '\u0003 \t\r\n')
                followed_by_whitespace = (index+1 >= len(scalar) or
                        scalar[index+1] in '\u0003 \t\r\n')

            # Let's decide what styles are allowed.
            var allow_flow_plain = true
            var allow_block_plain = true
            var allow_single_quoted = true
            var allow_double_quoted = true
            var allow_block = true

            # Leading and trailing whitespaces are bad for plain scalars.
            if (leading_space or leading_break
                    or trailing_space or trailing_break):
                allow_flow_plain = false
                allow_block_plain = false

            # We do not permit trailing spaces for block scalars.
            if trailing_space:
                allow_block = false

            # Spaces at the beginning of a new line are only acceptable for block
            # scalars.
            if break_space:
                allow_flow_plain = false
                allow_block_plain = false
                allow_single_quoted = false

            # Spaces followed by breaks, as well as special character are only
            # allowed for double quoted scalars.
            if space_break or special_characters:
                allow_flow_plain    = false
                allow_block_plain   = false
                allow_single_quoted = false
                allow_block = false

            # Although the plain scalar writer supports breaks, we never emit
            # multiline plain scalars.
            if line_breaks:
                allow_flow_plain = false
                allow_block_plain = false

            # Flow indicators are forbidden for flow plain scalars.
            if flow_indicators:
                allow_flow_plain = false

            # Block indicators are forbidden for block plain scalars.
            if block_indicators:
                allow_block_plain = false

            return {
                    scalar=scalar,
                    empty=false, 
                    multiline=line_breaks,
                    allow_flow_plain=allow_flow_plain,
                    allow_block_plain=allow_block_plain,
                    allow_single_quoted=allow_single_quoted,
                    allow_double_quoted=allow_double_quoted,
                    allow_block=allow_block
                }

        # Writers.

        static func flush_stream():
            if stream.has_method('flush'):
                stream.flush()

        static func write_stream_start():
            # Write BOM if needed.
            # if encoding and encoding.begins_with('utf-16'):
            #     stream.write('\uFEFF'.encode(encoding))
            #FIXME
            pass

        static func write_stream_end():
            flush_stream()

        static func write_indicator(indicator, need_whitespace,
                p_whitespace=false, p_indention=false):
            var data
            if whitespace or not need_whitespace:
                data = indicator
            else:
                data = ' '+indicator
            whitespace = p_whitespace
            indention = indention and p_indention
            column += len(data)
            open_ended = false
            if encoding:
                data = data.encode(encoding)
            stream.write(data)

        static func write_indent():
            var data
            var temp_indent = indent if indent != null else 0
            if not indention or column > temp_indent   \
                    or (column == temp_indent and not whitespace):
                write_line_break()
            if column < temp_indent:
                whitespace = true
                data = ' '.repeat(temp_indent-column)
                column = temp_indent
                if encoding:
                    data = data.encode(encoding)
                stream.write(data)

        static func write_line_break(data=null):
            if data == null:
                data = best_line_break
            whitespace = true
            indention = true
            line += 1
            column = 0
            if encoding:
                data = data.encode(encoding)
            stream.write(data)

        static func write_version_directive(version_text):
            var data = '%%YAML %s' % version_text
            if encoding:
                data = data.encode(encoding)
            stream.write(data)
            write_line_break()

        static func write_tag_directive(handle_text, prefix_text):
            var data = '%%TAG %s %s' % [handle_text, prefix_text]
            if encoding:
                data = data.encode(encoding)
            stream.write(data)
            write_line_break()

        # Scalar streams.

        static func write_single_quoted(text, split=true):
            write_indicator('\'', true)
            var spaces = false
            var breaks = false
            var start = 0
            var end = 0
            while end <= len(text):
                var ch = null
                if end < len(text):
                    ch = text[end]
                if spaces:
                    if ch == null or ch != ' ':
                        if start+1 == end and column > best_width and split   \
                                and start != 0 and end != len(text):
                            write_indent()
                        else:
                            var data = text.substr(start, end-start)
                            column += len(data)
                            if encoding:
                                data = data.encode(encoding)
                            stream.write(data)
                        start = end
                elif breaks:
                    if ch == null or ch not in '\n':
                        if text[start] == '\n':
                            write_line_break()
                        for br in text.substr(start, end-start):
                            if br == '\n':
                                write_line_break()
                            else:
                                write_line_break(br)
                        write_indent()
                        start = end
                else:
                    if ch == null or ch in ' \n' or ch == '\'':
                        if start < end:
                            var data = text.substr(start, end-start)
                            column += len(data)
                            if encoding:
                                data = data.encode(encoding)
                            stream.write(data)
                            start = end
                if ch == '\'':
                    var data = '\'\''
                    column += 2
                    if encoding:
                        data = data.encode(encoding)
                    stream.write(data)
                    start = end + 1
                if ch != null:
                    spaces = (ch == ' ')
                    breaks = (ch in '\n')
                end += 1
            write_indicator('\'', false)

        const ESCAPE_REPLACEMENTS = {
            '\u0003':       '0',
            # '\x07':     'a',
            # '\x08':     'b',
            # '\x09':     't',
            # '\x0A':     'n',
            # '\x0B':     'v',
            # '\x0C':     'f',
            # '\x0D':     'r',
            # '\x1B':     'e',
            '\"':       '\"',
            '\\':       '\\',
            # '\x85':     'N',
            # '\xA0':     '_',
            '\u2028':   'L',
            '\u2029':   'P',
        }

        static func write_double_quoted(text, split=true):
            write_indicator('"', true)
            var start = 0
            var end = 0
            while end <= len(text):
                var ch = null
                if end < len(text):
                    ch = text[end]
                # if ch == null or ch in '"\\\uFEFF' \
                #         or not ('\x20' <= ch <= '\x7E'
                #             or (allow_unicode
                #                 and ('\xA0' <= ch <= '\uD7FF'
                #                     or '\uE000' <= ch <= '\uFFFD'))):
                if ch == null or ch in '"\\\uFEFF' \
                        or not (allow_unicode and ('\uE000' <= ch <= '\uFFFD')):
                    if start < end:
                        var data = text.substr(start, end-start)
                        column += len(data)
                        if encoding:
                            data = data.encode(encoding)
                        stream.write(data)
                        start = end
                    if ch != null:
                        var data
                        if ch in ESCAPE_REPLACEMENTS:
                            data = '\\'+ESCAPE_REPLACEMENTS[ch]
                        # elif ch <= '\xFF':
                        #     data = '\\x%02X' % ord(ch)
                        elif ch <= '\uFFFF':
                            data = '\\u%04X' % ord(ch)
                        else:
                            data = '\\U%08X' % ord(ch)
                        column += len(data)
                        if encoding:
                            data = data.encode(encoding)
                        stream.write(data)
                        start = end+1
                if (0 < end and end < len(text)-1) and (ch == ' ' or start >= end)    \
                        and column+(end-start) > best_width and split:
                    var data = text.substr(start, end-start)+'\\'
                    if start < end:
                        start = end
                    column += len(data)
                    if encoding:
                        data = data.encode(encoding)
                    stream.write(data)
                    write_indent()
                    whitespace = false
                    indention = false
                    if text[start] == ' ':
                        data = '\\'
                        column += len(data)
                        if encoding:
                            data = data.encode(encoding)
                        stream.write(data)
                end += 1
            write_indicator('"', false)

        static func determine_block_hints(text):
            var hints = ''
            if text:
                if text[0] in ' \n':
                    hints += str(best_indent)
                if text[-1] not in '\n':
                    hints += '-'
                elif len(text) == 1 or text[-2] in '\n':
                    hints += '+'
            return hints

        static func write_folded(text):
            var hints = determine_block_hints(text)
            write_indicator('>'+hints, true)
            if not hints.is_empty() and hints[-1] == '+':
                open_ended = true
            write_line_break()
            var leading_space = true
            var spaces = false
            var breaks = true
            var start = 0
            var end = 0
            while end <= len(text):
                var ch = null
                if end < len(text):
                    ch = text[end]
                if breaks:
                    if ch == null or ch not in '\n':
                        if not leading_space and ch != null and ch != ' '   \
                                and text[start] == '\n':
                            write_line_break()
                        leading_space = (ch == ' ')
                        for br in text.substr(start, end-start):
                            if br == '\n':
                                write_line_break()
                            else:
                                write_line_break(br)
                        if ch != null:
                            write_indent()
                        start = end
                elif spaces:
                    if ch != ' ':
                        if start+1 == end and column > best_width:
                            write_indent()
                        else:
                            var data = text.substr(start, end-start)
                            column += len(data)
                            if encoding:
                                data = data.encode(encoding)
                            stream.write(data)
                        start = end
                else:
                    if ch == null or ch in ' \n':
                        var data = text.substr(start, end-start)
                        column += len(data)
                        if encoding:
                            data = data.encode(encoding)
                        stream.write(data)
                        if ch == null:
                            write_line_break()
                        start = end
                if ch != null:
                    breaks = (ch in '\n')
                    spaces = (ch == ' ')
                end += 1

        static func write_literal(text):
            var hints = determine_block_hints(text)
            write_indicator('|'+hints, true)
            if not hints.is_empty() and hints[-1] == '+':
                open_ended = true
            write_line_break()
            var breaks = true
            var start = 0
            var end = 0
            while end <= len(text):
                var ch = null
                if end < len(text):
                    ch = text[end]
                if breaks:
                    if ch == null or ch not in '\n':
                        for br in text.substr(start, end-start):
                            if br == '\n':
                                write_line_break()
                            else:
                                write_line_break(br)
                        if ch != null:
                            write_indent()
                        start = end
                else:
                    if ch == null or ch in '\n':
                        var data = text.substr(start, end-start)
                        if encoding:
                            data = data.encode(encoding)
                        stream.write(data)
                        if ch == null:
                            write_line_break()
                        start = end
                if ch != null:
                    breaks = (ch in '\n')
                end += 1

        static func write_plain(text, split=true):
            if root_context:
                open_ended = true
            if not text:
                return
            if not whitespace:
                var data = ' '
                column += len(data)
                if encoding:
                    data = data.encode(encoding)
                stream.write(data)
            whitespace = false
            indention = false
            var spaces = false
            var breaks = false
            var start = 0
            var end = 0
            while end <= len(text):
                var ch = null
                if end < len(text):
                    ch = text[end]
                if spaces:
                    if ch != ' ':
                        if start+1 == end and column > best_width and split:
                            write_indent()
                            whitespace = false
                            indention = false
                        else:
                            var data = text.substr(start, end-start)
                            column += len(data)
                            if encoding:
                                data = data.encode(encoding)
                            stream.write(data)
                        start = end
                elif breaks:
                    if ch not in '\n':
                        if text[start] == '\n':
                            write_line_break()
                        for br in text.substr(start, end-start):
                            if br == '\n':
                                write_line_break()
                            else:
                                write_line_break(br)
                        write_indent()
                        whitespace = false
                        indention = false
                        start = end
                else:
                    if ch == null or ch in ' \n':
                        var data = text.substr(start, end-start)
                        column += len(data)
                        if encoding:
                            data = data.encode(encoding)
                        stream.write(data)
                        start = end
                if ch != null:
                    spaces = (ch == ' ')
                    breaks = (ch in '\n')
                end += 1

    class StreamWrapper:
        var file
        var encoding :String
        var cache :String

        func _init(p_encoding:='utf8', p_file=null):
            if p_file is FileAccess and p_file.is_open():
                file = p_file
            encoding = p_encoding if encoding in ['utf8', 'utf16', 'utf32'] else 'utf8'

        func write(data):
            if file != null:
                file.store_buffer(data['to_%s_buffer' % encoding].call())
            else:
                cache += data

        func flush():
            if file is FileAccess and file.is_open():
                file.flush()

        func print_data():
            print(cache)