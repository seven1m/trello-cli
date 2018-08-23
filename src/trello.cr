# TODO: Write documentation for `Trello`

require "ncurses"
require "json"
require "http/client"
require "logger"

module Trello
  VERSION = "0.1.0"

  LOG = Logger.new(File.open("log.txt", "w"), level: Logger::DEBUG)

  class API
    SECRETS = JSON.parse(File.read(".secrets.json"))
    API_ROOT = "https://api.trello.com/1/"
    CREDENTIALS = "key=#{SECRETS["key"]}&token=#{SECRETS["token"]}"

    def self.get(path : String, params : String)
      response = HTTP::Client.get("#{API_ROOT}/#{path}?#{CREDENTIALS}&#{params}")
      JSON.parse(response.body)
    end
  end

  class ListSelectOption
    getter key, value

    def initialize(@key : String, @value : String)
    end
  end

  class ListSelectWindow
    getter win, height, width, title, parent, child, selected, active, json

    setter selected : Int8
    setter active : Bool
    setter title : String
    setter path : String
    setter params : String
    setter options : Array(ListSelectOption)
    setter board_id : String = ""

    WIDTH = 25
    HEIGHT = 15

    def initialize(x : Int32, y : Int32, height : Int32, width : Int32)
      @win = NCurses::Window.new(y: y, x: x, height: height, width: width)
      @selected = 0
      @width = width
      @height = height
      @title = ""
      @active = false
      @path = ""
      @params = ""
      @options = [] of ListSelectOption
    end

    def initialize(x : Int32, y : Int32, height : Int32, width : Int32, &block)
      initialize(x: x, y: y, height: height, width: width)
      yield self
    end

    def refresh
      win.erase
      win.border
      win.mvaddstr(title, x: 2, y: 0)

      y = 0

      @options.each_with_index do |option, i|
        if y >= height-2
          break
        end

        win.move(x: 1, y: y+=1)

        if i == @selected
          if @active
            win.attron(NCurses::Attribute::STANDOUT)
          end
        end
        win.addnstr(option.value, width-2)
        win.attroff(NCurses::Attribute::STANDOUT)
      end
      win.refresh
    end

    def handle_key(key)
      case key
      when NCurses::KeyCode::DOWN, 'j'
        if @selected < @options.size - 1
          @selected += 1
        end
      when NCurses::KeyCode::UP, 'k'
        if @selected > 0
          @selected -= 1
        end
      when NCurses::KeyCode::RETURN, NCurses::KeyCode::RIGHT, 'l'
        activate_child!(@options[@selected])
      when NCurses::KeyCode::LEFT, 'q', 'h' # Q, J
        # you can't get a truthy value out of an instance variable
        parent = @parent
        if parent
          @active = false
          parent.active = true
        end
      else
        LOG.debug("Unhandled key: #{key}")
      end
    end

    def link_parent(parent : ListSelectWindow)
      @parent = parent
      parent.link_child(self)
    end

    def link_child(child : ListSelectWindow)
      @child = child
    end

    def active?
      @active
    end

    def activate!
      json = API.get(@path, @params)
      json.as_a.each do |j|
        @options << ListSelectOption.new(key: j.as_h["id"].to_s, value: j.as_h["name"].to_s)
      end
    end

    def activate_child!(option)
    end
  end

  class BoardsWindow < ListSelectWindow

    def initialize
      super(x: 1, y: 1, height: 15, width: 25) do |win|
        win.path = "/members/me/boards"
        win.params = "fields=name,starred,shortUrl"
        win.active = true
        win.title = "Boards"
      end
    end

    def activate_child!(option : ListSelectOption)
      # you can't get a truthy value out of an instance variable
      child = @child
      if child
        @active = false
        child.active = true
        child.board_id = option.key
        child.options = [ListSelectOption.new(key: "d", value: option.key)]
      end
    end
  end

  class ListsWindow < ListSelectWindow
    property board_id : String = ""

    def initialize
      super(x: 1, y: 17, height: 15, width: 25) do |win|
        win.title = "Lists"
      end
    end
  end

  NCurses.open do
    NCurses.start_color
    NCurses.cbreak # CTRL-C breaks the program
    NCurses.noecho # Don't print characters as the user types
    NCurses.curs_set(0) # hide the cursor
    NCurses.keypad(true) # allows arrow and F# keys

    boards = BoardsWindow.new
    boards.activate!

    lists = ListsWindow.new
    lists.link_parent(boards)

    cards = ListSelectWindow.new x: 27, y: 1, height: NCurses.maxy - 2, width: NCurses.maxx - 28 do |win|
      win.title = "Cards"
    end
    cards.link_parent(lists)

    windows = [boards, lists, cards]

    selected = 0

    NCurses.refresh
    windows.each { |w| w.refresh }

    while true
      NCurses.notimeout(true)
      key = NCurses.getch
      windows.find(boards) { |w| w.active }.handle_key(key)

      NCurses.refresh
      windows.each { |w| w.refresh }
    end
  end
end