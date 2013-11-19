require 'fileutils'

class Gin::Worker

  def initialize pidfile, &block
    @pidfile = pidfile
    @pid     = nil
    @block   = block
  end


  def run
    FileUtils.touch(@pidfile)
    f = File.open(@pidfile, 'r+')
    return unless f.flock(File::LOCK_EX | File::LOCK_NB)

    if other_pid = f.read
      running = Process.kill(0, other_pid) rescue false
      return if running
    end

    @pid = fork do
      begin
        f.truncate(File.size(f.path))
        f.write Process.pid.to_s
        f.flush
        @block.call
      rescue Interrupt
        $stderr.puts "Worker Interrupted: #{@pidfile} (#{Process.pid})"
      ensure
        f.close unless f.closed?
        File.delete(f.path)
      end
    end

  ensure
    f.close if f && !f.closed?
  end


  def kill sig="INT"
    Process.kill(sig, @pid) if @pid
  end


  def wait
    Process.waitpid(@pid) if @pid
  end
end
