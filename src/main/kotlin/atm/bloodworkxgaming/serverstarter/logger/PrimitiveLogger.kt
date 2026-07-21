package atm.bloodworkxgaming.serverstarter.logger

import okio.Okio
import okio.buffer
import okio.sink
import org.fusesource.jansi.Ansi
import java.io.File
import java.io.IOException
import java.io.PrintWriter
import java.io.StringWriter
import java.time.LocalTime
import java.time.format.DateTimeFormatter

class PrimitiveLogger(outputFile: File) {
    private val pattern = "\\x1b\\[[0-9;]*m".toRegex()
    private val dateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm:ss")
    // The truncate has to happen before the sink opens the file. Doing it the other way around
    // unlinks the file the sink is already holding open, so on Linux no log ever shows up on disk.
    private val bufferedSink = run {
        if (outputFile.exists()) {
            outputFile.delete()
        }
        outputFile.sink().buffer()
    }

    init {
        // Nothing else flushes this sink, so without the hook the tail of the log (which is the
        // part you actually want after a crash) is lost when the JVM exits.
        Runtime.getRuntime().addShutdownHook(Thread {
            synchronized(this) {
                try {
                    bufferedSink.flush()
                } catch (e: IOException) {
                    System.err.println("Could not flush the log file: ${e.message}")
                }
            }
        })
    }

    @JvmOverloads
    fun info(message: Any?, logOnly: Boolean = false) {
        val m = currentTimeAnsi().fgYellow().a("[INFO] ").fgDefault().a(message).reset().newline().toString()

        synchronized(this) {
            try {
                bufferedSink.writeUtf8(stripColors(m))
            } catch (e: IOException) {
                error("Error while logging!", e)
            }

            if (!logOnly) {
                print(m)
            }
        }
    }

    fun warn(message: Any?) {
        val m = currentTimeAnsi().fgMagenta().a("[WARNING] ").bgDefault().a(message).reset().newline().toString()

        synchronized(this) {
            try {
                bufferedSink.writeUtf8(stripColors(m))
            } catch (e: IOException) {
                error("Error while logging!", e)
            }

            print(m)
        }
    }

    fun error(message: Any?, throwable: Throwable? = null) {
        var m = currentTimeAnsi().fgRed().a("[ERROR] ").bgDefault().a(message).reset().newline().toString()

        if (throwable != null) {
            val sw = StringWriter()
            throwable.printStackTrace(PrintWriter(sw))
            m += "\n" + sw.toString()
        }

        synchronized(this) {
            try {
                bufferedSink.writeUtf8(stripColors(m))
            } catch (e: IOException) {
                System.err.println("Error while logging!")
                e.printStackTrace()
            }

            print(m)
        }
    }

    private fun stripColors(message: String): String {
        return pattern.replace(message, "")
    }

    private fun currentTimeAnsi(): Ansi {
        return Ansi.ansi().fgBrightBlack().a("[" + LocalTime.now().format(dateTimeFormatter) + "] ").fgDefault()
    }
}
