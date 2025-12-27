extends Control

var test_array :Array[Test]
var tag_dic :Dictionary

func _ready():
    reload_test_files()
    exec_tests()

    # YAML.register_class(MyCustomClass)
    # YAML.register_class(MyCustomClass, "serialize", "deserialize")
    # var yaml_string = FileAccess.open("./doc/supported_syntax.yaml", FileAccess.READ).get_as_text()
    # pirnt(YAML.load(yaml_string))
    # print(YAML.dump(YAML.load(yaml_string))
    # var dump_1 = YAML.dump(YAML.load(yaml_string))
    # var dump_2 = YAML.dump(YAML.load(YAML.dump(YAML.load(yaml_string))))
    # print(dump_1 == dump_2) # Should be true
    # YAML.save_file(YAML.load(YAML.dump(YAML.load(yaml_string))), "./doc/dumped_supported_syntax-new.yaml")

const skip_tag = [
    "empty-key",
    # We're skipping this tag because PyYAML ​​doesn't implement the corresponding functionality; 
    # they will throw errors, and they should be considered errors, 
    # but they don't have corresponding error files, 
    # which is a bit confusing. See the following link for details：
    # https://github.com/yaml/yaml-test-suite/pull/40
    # https://github.com/yaml/yaml-test-suite/issues/25
]

func reload_test_files():
    var test_file_dir_path = "res://test_data/yaml-test-suite-data-2022-01-17"
    var tag_dir_path = test_file_dir_path+"/tags"
    for tag_name in DirAccess.get_directories_at(tag_dir_path):
        tag_dic[tag_name] = []
        for test_id in DirAccess.get_files_at(tag_dir_path+"/"+tag_name):
            tag_dic[tag_name].append(test_id)
        for group_test_id in DirAccess.get_directories_at(tag_dir_path+"/"+tag_name):
            for sub_test_number in DirAccess.get_directories_at(tag_dir_path+"/"+tag_name+"/"+group_test_id):
                var test_id = group_test_id+"/"+sub_test_number
                tag_dic[tag_name].append(test_id)

    for dir_name in DirAccess.get_directories_at(test_file_dir_path):
        if dir_name not in ["name", "tags"]: # Ignore these two metadata directories
            var sub_dir_path = test_file_dir_path + "/" + dir_name
            if DirAccess.get_directories_at(sub_dir_path).size() == 0:
                test_array.append(Test.new(sub_dir_path, tag_dic))
            else:
                for sub_test_number in DirAccess.get_directories_at(sub_dir_path):
                    var sub_sub_dir_path = sub_dir_path + "/%s" % sub_test_number
                    test_array.append(Test.new(sub_sub_dir_path, tag_dic))

    $%TestFileTree.clear()
    $%TestFileTree.set_column_title(0, "ID")
    $%TestFileTree.set_column_title(1, "Name")
    $%TestFileTree.set_column_title(2, "Status")
    $%TestFileTree.set_column_title(3, "JSON_Status")
    $%TestFileTree.set_column_expand_ratio(1,4)

    $%TotalNumberLabel.text = "Total number of tests: %d" % test_array.size()


func exec_tests():
    var test_file_tree_root = $%TestFileTree.create_item()

    test_array.sort_custom(func(a, b): return a.name < b.name)
    for test in test_array:
        var test_treeitem = $%TestFileTree.create_item(test_file_tree_root)
        if test.tags.all(func(tag): return tag not in skip_tag):
            test.exec()
        else:
            test.status = "Skipped"

        test_treeitem.set_text(0, test.id)
        test_treeitem.set_text(1, test.name)
        test_treeitem.set_text(2, test.status)

        var color = Color.GREEN if test.status == "Passed" else Color.RED
        test_treeitem.set_custom_color(2, color)
        if test.status == "Skipped":
            test_treeitem.set_custom_color(2, Color.YELLOW)
        if test.status == "Pending":
            test_treeitem.set_custom_color(2, Color.GRAY)

        test.exec_json_test()
        test_treeitem.set_text(3, test.json_test_status)

        color = Color.GREEN if test.json_test_status == "Passed" else Color.RED
        test_treeitem.set_custom_color(3, color)
        if test.json_test_status == "Skipped":
            test_treeitem.set_custom_color(3, Color.YELLOW)
        if test.json_test_status == "Pending":
            test_treeitem.set_custom_color(3, Color.GRAY)
        if test.json_test_status == "Ignored":
            test_treeitem.set_custom_color(3, Color.DARK_GRAY)


    $%FailedLabel.text = "Failed: [color=red]%d[/color]" % test_array.reduce(func(count, next): return count +1 if next.status == "Failed" else count, 0)
    $%PassedLabel.text = "Passed: [color=green]%d[/color]" % test_array.reduce(func(count, next): return count +1 if next.status == "Passed" else count, 0)
    $%SkippedLabel.text = "Skipped: [color=yellow]%d[/color]" % test_array.reduce(func(count, next): return count +1 if next.status == "Skipped" else count, 0)

    $%JSONFailedLabel.text = "Failed: [color=red]%d[/color]" % test_array.reduce(func(count, next): return count +1 if next.json_test_status == "Failed" else count, 0)
    $%JSONPassedLabel.text = "Passed: [color=green]%d[/color]" % test_array.reduce(func(count, next): return count +1 if next.json_test_status == "Passed" else count, 0)
    $%JSONSkippedLabel.text = "Skipped: [color=yellow]%d[/color]" % test_array.reduce(func(count, next): return count +1 if next.json_test_status == "Skipped" else count, 0)
    $%JSONIgnoredLabel.text = "Ignored: [color=darkgray]%d[/color]" % test_array.reduce(func(count, next): return count +1 if next.json_test_status == "Ignored" else count, 0)


class Test:
    var id :String
    var name :String # Title/Label
    var tags :Array[String]
    var status :String = "Pending"
    var json_test_status :String = "Pending"

    var _file_path :String
    var _in_yaml :String
    var _test_event :String
    var _in_json :String
    var _out_yaml :String
    var _should_be_error :bool = false
    var _emit_yaml :String

    func _init(p_file_path:String, tag_dic:Dictionary):
        var regex = RegEx.create_from_string(r"^res://.+/(?<id>\w{4}(?:/\d{2,3})?)$")
        var result= regex.search(p_file_path)

        assert(result != null)
        id = result.get_string("id")
        assert(FileAccess.file_exists(p_file_path + "/==="))
        name = FileAccess.open(p_file_path + "/===", FileAccess.READ).get_as_text()

        for tag in tag_dic:
            if id in tag_dic[tag]:
                tags.append(tag)

        _file_path = p_file_path
        assert(FileAccess.file_exists(p_file_path + "/in.yaml"))
        _in_yaml = FileAccess.open(p_file_path + "/in.yaml", FileAccess.READ).get_as_text()

        if FileAccess.file_exists(p_file_path + "/test.event"):
            _test_event = FileAccess.open(p_file_path + "/test.event", FileAccess.READ).get_as_text()

        if FileAccess.file_exists(p_file_path + "/in.json"):
            _in_json = FileAccess.open(p_file_path + "/in.json", FileAccess.READ).get_as_text()
 
        if FileAccess.file_exists(p_file_path + "/out.yaml"):
            _out_yaml = FileAccess.open(p_file_path + "/out.yaml", FileAccess.READ).get_as_text()

        if FileAccess.file_exists(p_file_path + "/error"):
            _should_be_error = true

        if FileAccess.file_exists(p_file_path + "/emit.yaml"):
            _emit_yaml = FileAccess.open(p_file_path + "/emit.yaml", FileAccess.READ).get_as_text()

    func exec():
        var result_events = YAML.parse_to_events(_in_yaml)

        if result_events == _test_event:
            status = "Passed"
        else:
            if _should_be_error and YAML.has_error():
                status = "Passed"
            else:
                status = "Failed"

    func exec_json_test():
        if _in_json.is_empty(): json_test_status = "Ignored"
        if status == "Failed":  json_test_status = "Failed"
        if status == "Passed" and _should_be_error:  json_test_status = "Passed"

        if status != "Failed" and not _should_be_error and not _in_json.is_empty():
            var result = YAML.parse(_in_yaml).get_data()
            var json = JSON.new()
            var error = json.parse(_in_json)
            if error == OK:
                var except_json = JSON.stringify(json.data)
                var result_json = JSON.stringify(JSON.parse_string(JSON.stringify(result))) # ridiculous Godot

                if except_json == result_json:
                    json_test_status = "Passed"
                
                if except_json != result_json:
                    json_test_status = "Failed"
                    # print(id)
                    # print("ex:\n", except_json)
                    # print("re:\n", result_json)
            else:
                json_test_status = "Skipped"