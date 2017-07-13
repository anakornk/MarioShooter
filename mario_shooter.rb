require 'rubygems'
require 'gosu'

WIDTH, HEIGHT = 1024, 768

module Tiles
  Brick1 = 0
  Brick2 = 1
end

module Color
  Red = "media/mario1.png"
  Blue = "media/mario2.png"
end

# Fireballs
class FireBall
  attr_reader :x, :y, :at_player

  def initialize(x, y,dir, map, at_player)
    @image = Gosu::Image.new("media/fireball.png")
    if dir == :left
      @x = x - 20
    else
      @x = x + 20
    end
    @y = y - 25
    @dir = dir
    @map = map
    @at_player = at_player
  end

  def update
    if @dir == :left
      @x = @x - 5
    else
       @x = @x + 5
    end
  end

  def draw
    # draw fireballs
    @image.draw_rot(@x, @y, 0, 25 * Math.sin(Gosu.milliseconds / 133.7))
  end

  def hit_wall
    # check if collides with the map
    @map.solid?(@x, @y)
  end

  def hit_player
    # check if the opponent is hit
    (@x > @at_player.x - 25) && (@x < @at_player.x + 25) &&  (@y > @at_player.y - 50) && (@y < @at_player.y)
  end
end

# Player class.
class Player
  attr_reader :x, :y, :health, :dead

  def initialize(map, x, y,type)
    @x, @y = x, y
    @dir = :left
    @vy = 0 # Vertical velocity
    @map = map

    arr = Gosu::Image.load_tiles(type, 50, 50)
    @standing = arr[-1]
    @walk1 = arr[-2]
    @walk2 = arr[-3]
    @jump = arr[-10]
    # This always points to the frame that is currently drawn.
    # This is set in update, and used in draw.
    @cur_image = @standing
    @fireball_arr = []
    @health = 100
    @dead = false
  end

  def subtract_heath
    if @health <= 0
      @dead = true
    else
      @health -= 10
    end
  end

  def draw
    # Flip vertically when facing to the left.
    if @dir == :left
      offs_x = -25
      factor = 1.0
    else
      offs_x = 25
      factor = -1.0
    end
    @cur_image.draw(@x + offs_x, @y - 49, 0, factor, 1.0)
    draw_fireball
  end

  # Could the object be placed at x + offs_x/y + offs_y without being stuck?
  def would_fit(offs_x, offs_y)
    # Check at the center/top and center/bottom for map collisions
    not @map.solid?(@x + offs_x, @y + offs_y) and
      not @map.solid?(@x + offs_x, @y + offs_y - 45)
  end

  def update(move_x)
    # Select image depending on action
    if (move_x == 0)
      @cur_image = @standing
    else
      @cur_image = (Gosu.milliseconds / 175 % 2 == 0) ? @walk1 : @walk2
    end
    if (@vy < 0)
      @cur_image = @jump
    end

    # Directional walking, horizontal movement
    if move_x > 0
      @dir = :right
      move_x.times { if would_fit(1, 0) then @x += 1 end }
    end
    if move_x < 0
      @dir = :left
      (-move_x).times { if would_fit(-1, 0) then @x -= 1 end }
    end

    # Acceleration/gravity
    # By adding 1 each frame, and (ideally) adding vy to y, the player's
    # jumping curve will be the parabole we want it to be.
    @vy += 1
    # Vertical movement
    if @vy > 0
      @vy.times { if would_fit(0, 1) then @y += 1 else @vy = 0 end }
    end
    if @vy < 0
      (-@vy).times { if would_fit(0, -1) then @y -= 1 else @vy = 0 end }
    end
  end

  def try_to_jump
    if @map.solid?(@x, @y + 1)
      @vy = -20
    end
  end

  def shoot_at(at_player)
    fireball = FireBall.new(@x,@y, @dir,@map, at_player)
    @fireball_arr << fireball
  end

  def draw_fireball
    @fireball_arr.each do |fireball|
      fireball.draw
    end
  end

  def update_fireball
    @fireball_arr.select! do |fireball|
      if fireball.hit_player
        fireball.at_player.subtract_heath
      end
      !fireball.hit_wall && !fireball.hit_player
    end

    @fireball_arr.each do |fireball|
      fireball.update
    end
  end
end

# Map class holds and draws tiles and gems.
class Map
  attr_reader :width, :height, :gems

  def initialize(filename)
    # Load 60x60 tiles, 5px overlap in all four directions.
    # x = Gosu::Image.load_tiles("media/brick1.png", 50, 50, :tileable => true)
    brick1 = Gosu::Image.new("media/brick1.png")
    brick2 = Gosu::Image.new("media/brick2.png")
    @tileset = [brick1,brick2]

    lines = File.readlines(filename).map { |line| line.chomp }
    @height = lines.size
    @width = lines[0].size
    @tiles = Array.new(@width) do |x|
      Array.new(@height) do |y|
        case lines[y][x, 1]
        when '"'
          Tiles::Brick1
        when '#'
          Tiles::Brick2
        else
          nil
        end
      end
    end
  end

  def draw
    # Very primitive drawing function:
    # Draws all the tiles, some off-screen, some on-screen.
    @height.times do |y|
      @width.times do |x|
        tile = @tiles[x][y]
        if tile
          # Draw the tile with an offset (tile images have some overlap)
          # Scrolling is implemented here just as in the game objects.
          @tileset[tile].draw(x * 50 - 5, y * 50 - 5, 0)
        end
      end
    end
  end

  # Solid at a given pixel position?
  def solid?(x, y)
    y < 0 || @tiles[x / 50][y / 50]
  end
end

class MarioShooter < (Gosu::Window)
  def initialize
    super WIDTH, HEIGHT

    self.caption = "Mario Shooter"
    @sky = Gosu::Image.new("media/bg32.jpg", :tileable => true)
    @map = Map.new("media/map.txt")
    init_game
  end

  def init_game
    @mario1 = Player.new(@map, 200, 100,Color::Red)
    @mario2 = Player.new(@map, 800, 100,Color::Blue)
    # The scrolling position is stored as top left corner of the screen.
    @camera_x = @camera_y = 0
    @health_bar_font = Gosu::Font.new(20)
    @end_message_font = Gosu::Font.new(60)
    @game_end = false
  end
  def update
    if @mario1.dead || @mario2.dead
      @game_end = true
      return
    end

    # Mario 1 movement
    move1_x = 0
    if Gosu.button_down? Gosu::KB_A
      move1_x -= 5
    elsif Gosu.button_down? Gosu::KB_D
      move1_x += 5
    end
    @mario1.update(move1_x)
    @mario1.update_fireball

    # Mario 2 movement
    move2_x = 0
    if Gosu.button_down? Gosu::KB_LEFT
      move2_x -= 5
    elsif Gosu.button_down? Gosu::KB_RIGHT
      move2_x += 5
    end
    @mario2.update(move2_x)
    @mario2.update_fireball


    # Scrolling follows the mid x of two players
    mid_x = (@mario1.x + @mario2.x) /2
    @camera_x = [[mid_x - WIDTH / 2, 0].max, @map.width * 50 - WIDTH].min
    @camera_y = [[@mario1.y - HEIGHT / 2, 0].max, @map.height * 50 - HEIGHT].min
  end

  def draw
    @sky.draw(0, 0, 0)
    Gosu.translate(-@camera_x, -@camera_y) do
      @map.draw
      if !@mario1.dead
        @mario1.draw
      end
      if !@mario2.dead
        @mario2.draw
      end
    end
    @health_bar_font.draw("Health: #{@mario1.health}", 10, 10, 3, 1.0, 1.0, Gosu::Color::RED)
    @health_bar_font.draw("Health: #{@mario2.health}", 900, 10, 3, 1.0, 1.0, Gosu::Color::BLUE)
    if @mario1.dead
      @end_message_font.draw("Blue Mario Wins", 350, 300, 3, 1.0, 1.0, Gosu::Color::BLUE)
      @health_bar_font.draw("Press 'C' to play again", 350, 10, 3, 1.0, 1.0, Gosu::Color::YELLOW)
    elsif @mario2.dead
      @end_message_font.draw("Red Mario Wins", 350, 300, 3, 1.0, 1.0, Gosu::Color::RED)
      @health_bar_font.draw("Press 'C' to play again", 350, 10, 3, 1.0, 1.0, Gosu::Color::YELLOW)
    end

  end

  def button_down(id)
    case id
    when Gosu::KB_UP
      @mario2.try_to_jump
    when Gosu::KB_SPACE
      @mario1.shoot_at(@mario2)
    when Gosu::KB_W
      @mario1.try_to_jump
    when Gosu::KB_RETURN
        @mario2.shoot_at(@mario1)
    when Gosu::KB_C
      if @game_end
        init_game
      end
    when Gosu::KB_ESCAPE
      close
    else
      super
    end
  end
end

MarioShooter.new.show if __FILE__ == $0
