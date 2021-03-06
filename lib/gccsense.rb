require 'fileutils'

module Redcar
  class GCCSense
    def self.menus
      Menu::Builder.build do
        sub_menu "Plugins" do
          sub_menu "GCCSense" do
            item "code completion", GCCSense::CodeCompleteCommand
            item "key binding", GCCSense::ChangeKeyComboCommand
            item "change gccsense suffix", GCCSense::ChangeGccSuffix
          end
        end
      end
    end
    
    def self.suffix
      GCCSense.storage["gcc_suffix"] || "-code-assist"
    end
    
    def self.suffix=(suffix)
      GCCSense.storage["gcc_suffix"] = suffix
    end
    
    def self.gccrec
      GCCSense.storage["gccrec_suffix"] || "gccrec"
    end
    
    def self.gccrec=(suffix)
      GCCSense.storage["gccrec_suffix"] = suffix
    end
    
    def self.auto_pch_suffix
      GCCSense.storage["auto_pch_suffix"] || "autopch"
    end
    
    def self.auto_pch_suffix=(suffix)
      GCCSense.storage["auto_pch_suffix"] = suffix
    end
    
    def self.auto_pch
      @auto_pch || "-a #{auto_pch_suffix}"
    end
    
    def self.toggle_auto_pch
      if @auto_pch == ""
        @auto_pch = "-a #{auto_pch_suffix}"      
      else
        @auto_pch = ""
      end
    end
    
    
        
    def self.storage
      @storage ||= Plugin::Storage.new('gccsense_plugin')
    end
    
    def self.key_combo
      if Redcar.platform == :osx
        GCCSense.storage["key_combo"] || "Cmd+Shift+C"
      else
        GCCSense.storage["key_combo"] || "Ctrl+Shift+C"
      end
    end
    
    def self.key_combo=(key)
      old_key = key_combo
      old_key_string = Redcar::ApplicationSWT::Menu::BindingTranslator.platform_key_string(old_key)
      item = Redcar::ApplicationSWT::Menu.items[old_key_string]
      Redcar::ApplicationSWT::Menu.items.delete(old_key_string)
      Redcar.app.main_keymap.map.delete(old_key)
      GCCSense.storage["key_combo"] = key
      Redcar.app.main_keymap.map[key] = GCCSense::CodeCompleteCommand
      key_string = Redcar::ApplicationSWT::Menu::BindingTranslator.platform_key_string(key)
      item.first.text = item.first.text.split("\t").first + "\t" + key_string
      item.first.set_accelerator(Redcar::ApplicationSWT::Menu::BindingTranslator.key(key_string))
      Redcar::ApplicationSWT::Menu.items[key_string] = item
    end
    
    def self.keymaps
      linwin = Keymap.build("main", [:linux, :windows]) do
        link Redcar::GCCSense.key_combo, GCCSense::CodeCompleteCommand
      end

      osx = Keymap.build("main", :osx) do
        link Redcar::GCCSense.key_combo, GCCSense::CodeCompleteCommand
      end

      [linwin, osx]
    end
    
    class ChangeKeyComboCommand < Command
      def execute
        result = Application::Dialog.input("Key Combination", "Please enter new key combo (i.e. 'Ctrl+Shift+C')", Redcar::GCCSense.key_combo) do |text|
          unless text == ""
            nil
          else
            "invalid combination"
          end
      	end
        Redcar::GCCSense.key_combo = result[:value] if result[:button ] == :ok
      end
    end
    
    class ChangeGccSuffix < Command
      def execute
        result = Application::Dialog.input("GCCSense suffix", "Please enter gcc suffix (i.e. '-code-assist' => 'gcc-code-assist'))", Redcar::GCCSense.suffix) do |text|
          unless text == ""
            nil
          else
            "invalid suffix"
          end
      	end
        Redcar::GCCSense.suffix = result[:value] if result[:button ] == :ok
      end
    end
    
    class RecordComiplerOptions < EditTabCommand
      
    end

    class CodeCompleteCommand < EditTabCommand      
      
      def execute
        path = doc.mirror.path.split(/\/|\\/)
        if path.last.split(".").last =~ /h|c|cpp|cc|cxx|CPP|CC|CXX/
          path[path.length-1]= ".gccsense." + path.last
          path = path.join("/")
          cursor_line_number = doc.cursor_line
          cursor_line_str = doc.get_line(cursor_line_number)
          cursor_line_offset = doc.cursor_line_offset
          cursor_offset = doc.cursor_offset
          cursor_line_end_offset = doc.cursor_line_end_offset
          line_str = cursor_line_str.rstrip
          new_line_length = cursor_line_str.length - line_str.length
          line_end_length = line_str.length - cursor_line_offset
          line_str = line_str[0..(cursor_line_offset-1)]          
          line_split = line_str.split(/::|\.|->/)        
          prefix = ""
          prefix = line_split.last unless line_str[line_str.length-1].chr =~ /:|\.|>/
          prefix_start_offset = doc.cursor_line_offset - prefix.length

          doc_str = doc.to_s[0..(cursor_offset-prefix.length-1)] + doc.to_s[(cursor_line_end_offset-new_line_length)..(doc.to_s.length-1)]
          
          File.open(path, "wb") {|f| f.print doc_str }
          completions = get_completions(path, prefix, prefix_start_offset)
          
          cur_doc = doc
          builder = Menu::Builder.new do
            completions.each do |current_completion|            
              item(current_completion[0] + "\t" + current_completion[1]) do              
                cur_doc.replace(cur_doc.cursor_offset - prefix.length, prefix.length, current_completion[0])
              end
            end
          end
          
          window = Redcar.app.focussed_window
          location = window.focussed_notebook.focussed_tab.controller.edit_view.mate_text.viewer.getTextWidget.getLocationAtOffset(window.focussed_notebook.focussed_tab.controller.edit_view.cursor_offset)
          absolute_x = location.x
          absolute_y = location.y
          location = window.focussed_notebook.focussed_tab.controller.edit_view.mate_text.viewer.getTextWidget.toDisplay(0,0)
          absolute_x += location.x
          absolute_y += location.y
          menu = ApplicationSWT::Menu.new(window.controller, builder.menu, nil, Swt::SWT::POP_UP)
          menu.move(absolute_x, absolute_y)
          menu.show
          FileUtils.rm(path)
        end
      end
      
      def get_gccsense_driver
        if doc.mirror.path.split(/\/|\\/).last =~ /cpp|cc|cxx|CPP|CC|CXX/
          "g++" + GCCSense.suffix
        else
          "gcc" + GCCSense.suffix
        end
      end
      
      def get_completions(temp_path, prefix, offset_at_line)
        line_offset = doc.cursor_line
        words = []
        filename = doc.mirror.path          
        command = "'#{GCCSense.gccrec}' -r '#{GCCSense.auto_pch}' -d #{get_gccsense_driver} -a \"#{temp_path}\" \"#{filename}\" -fsyntax-only \"-code-completion-at=#{temp_path}:#{line_offset+1}:#{offset_at_line+2}\""
        log(command)
        result = `#{command}`        
        result = result.split("\n")
        completions = []
        result.each do |item|
          if item =~ /^completion: #{prefix}/
            item_a = item.split(" ")            
            if item_a[2].length > 35
              completions << [item_a[1], item_a[2][0...35] + "..."]
            else
              completions << [item_a[1], item_a[2]]
            end
          end
        end
        completions.uniq
      end

      def log(message)
        puts("==> GCCSense: #{message}")
      end
    end
  end
end
