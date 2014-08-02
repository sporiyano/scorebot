class Availability < ActiveRecord::Base
  belongs_to :instance
  belongs_to :round
  belongs_to :token
  scope :failed, -> { where.not(status: 0) }
  has_many :penalties

  def self.check(instance, round)
    candidate = new instance: instance, round: round
    candidate.check
    return candidate
  end

  def check
    service_name = instance.service.name
    team_address = instance.team.address

    script = Rails.root.join('scripts', service_name, 'availability')

    Dir.chdir File.dirname script
    shell = ShellProcess.
      new(
          script,
          team_address
          )
    
    self.status = shell.status
    self.memo = shell.output
    load_dinguses

    self
  end

  def healthy?
    status == 0
  end

  def as_movement_json
    return { availability: { id: id, healthy: true } } if healthy?

    return as_json include_root: true, only: %i{ id penalties }
  end

  def load_dinguses
    if has_token = /^!!legitbs-validate-token (.+)$/.match(memo)
      self.token_string = has_token[1]
      self.token = Token.from_token_string self.token_string
    end
    
    if has_dingus = /^!!legitbs-validate-dev-ctf (.+)$/.match(memo)
      self.dingus = Base64.decode64 has_dingus[1]
    end
  end

  def distribute!
    flags = instance.team.flags.limit(19)

    return distribute_parking(flags) if flags.count < 19
    return distribute_everywhere(flags)
  end

  private
  def distribute_everywhere(flags)
    teams = Team.where('id != ? and id != ?', 
                       Team.legitbs.id, 
                       instance.team.id)

    Scorebot.log "reallocating #{flags.length} from #{instance.team.name} #{instance.service.name} flags to #{teams} teams"

    flags.each do |f|
      t = teams.pop
      f.team = t
      f.save
    end
  end

  def distribute_parking(flags)
    flags.each do |f|
      f.team = Team.legitbs
      f.save
    end
  end
end
