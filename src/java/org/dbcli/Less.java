/*
 * Copyright (c) 2002-2018, the original author or authors.
 *
 * This software is distributable under the BSD license. See the terms of the
 * BSD license in the documentation provided with this software.
 *
 * https://opensource.org/licenses/BSD-3-Clause
 */
package org.dbcli;

import org.jline.builtins.Source;
import org.jline.keymap.BindingReader;
import org.jline.keymap.KeyMap;
import org.jline.terminal.Attributes;
import org.jline.terminal.Size;
import org.jline.terminal.Terminal;
import org.jline.terminal.Terminal.Signal;
import org.jline.terminal.Terminal.SignalHandler;
import org.jline.utils.*;
import org.jline.utils.InfoCmp.Capability;

import java.io.InputStreamReader;
import java.io.*;
import java.util.*;
import java.util.regex.Pattern;
import java.util.regex.PatternSyntaxException;

import static org.jline.keymap.KeyMap.*;

public class Less {

    private static final int ESCAPE = 27;

    public boolean quitAtSecondEof;
    public boolean quitAtFirstEof;
    public boolean quitIfOneScreen;
    public boolean printLineNumbers;
    public boolean quiet;
    public boolean veryQuiet;
    public boolean chopLongLines;
    public boolean ignoreCaseCond;
    public boolean ignoreCaseAlways;
    public boolean noKeypad;
    public boolean noInit;
    public int padding = 0;
    public int tabs = 4;
    public int numWidth = 4;

    protected final Terminal terminal;
    protected final Play display;
    protected final BindingReader bindingReader;

    protected List<Source> sources;
    protected int sourceIdx;
    protected BufferedReader reader;
    protected KeyMap<Operation> keys;

    protected int firstLineInMemory = 0;
    protected List<AttributedString> lines = new ArrayList<>();

    protected int firstLineToDisplay = 0;
    protected int firstColumnToDisplay = 0;
    protected int offsetInLine = 0;

    protected String message;
    protected final StringBuilder buffer = new StringBuilder();

    protected final Map<String, Operation> options = new TreeMap<>();

    protected int window;
    protected int halfWindow;

    protected int nbEof;

    protected String pattern;

    protected final Size size = new Size();

    private int titleLines = 0;
    private AttributedString[] titles = new AttributedString[titleLines];
    private boolean fullRefresh = false;

    public Less(Terminal terminal) {
        this.terminal = terminal;
        this.display = new Play(terminal);
        this.bindingReader = new BindingReader(terminal.reader());
    }

    public void setTitleLines(int titleLines) {
        this.titleLines = titleLines;
        titles = new AttributedString[titleLines];
    }

    public void handle(Signal signal) {
        size.copy(terminal.getSize());
        try {
            display.clear();
            display(false);
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    public void run(Source... sources) throws IOException, InterruptedException {
        run(Arrays.asList(sources));
    }

    public void run(List<Source> sources) throws IOException, InterruptedException {
        if (sources == null || sources.isEmpty()) {
            throw new IllegalArgumentException("No sources");
        }
        this.sources = sources;

        sourceIdx = 0;
        openSource();

        try {
            size.copy(terminal.getSize());

            if (quitIfOneScreen && sources.size() == 1) {
                if (display(true)) {
                    return;
                }
            }

            SignalHandler prevHandler = terminal.handle(Signal.WINCH, this::handle);
            Attributes attr = terminal.enterRawMode();
            try {
                keys = new KeyMap<>();
                bindKeys(keys);
                display.init(!noInit);
                if (!noKeypad) {
                    terminal.puts(Capability.keypad_xmit);
                }
                terminal.writer().flush();

                display(false);
                checkInterrupted();

                options.put("-e", Operation.OPT_QUIT_AT_SECOND_EOF);
                options.put("--quit-at-eof", Operation.OPT_QUIT_AT_SECOND_EOF);
                options.put("-E", Operation.OPT_QUIT_AT_FIRST_EOF);
                options.put("-QUIT-AT-EOF", Operation.OPT_QUIT_AT_FIRST_EOF);
                options.put("-N", Operation.OPT_PRINT_LINES);
                options.put("--LINE-NUMBERS", Operation.OPT_PRINT_LINES);
                options.put("-q", Operation.OPT_QUIET);
                options.put("--quiet", Operation.OPT_QUIET);
                options.put("--silent", Operation.OPT_QUIET);
                options.put("-Q", Operation.OPT_VERY_QUIET);
                options.put("--QUIET", Operation.OPT_VERY_QUIET);
                options.put("--SILENT", Operation.OPT_VERY_QUIET);
                options.put("-S", Operation.OPT_CHOP_LONG_LINES);
                options.put("--chop-long-lines", Operation.OPT_CHOP_LONG_LINES);
                options.put("-i", Operation.OPT_IGNORE_CASE_COND);
                options.put("--ignore-case", Operation.OPT_IGNORE_CASE_COND);
                options.put("-I", Operation.OPT_IGNORE_CASE_ALWAYS);
                options.put("--IGNORE-CASE", Operation.OPT_IGNORE_CASE_ALWAYS);

                Operation op;
                do {
                    checkInterrupted();
                    size.copy(terminal.getSize());
                    window = size.getRows() - 1;
                    halfWindow = window / 2;
                    op = null;
                    //
                    // Option edition
                    //
                    if (buffer.length() > 0 && buffer.charAt(0) == '-') {
                        int c = terminal.reader().read();
                        message = null;
                        if (buffer.length() == 1) {
                            buffer.append((char) c);
                            if (c != '-') {
                                op = options.get(buffer.toString());
                                if (op == null) {
                                    message = "There is no " + printable(buffer.toString()) + " option";
                                    buffer.setLength(0);
                                }
                            }
                        } else if (c == '\r') {
                            op = options.get(buffer.toString());
                            if (op == null) {
                                message = "There is no " + printable(buffer.toString()) + " option";
                                buffer.setLength(0);
                            }
                        } else {
                            buffer.append((char) c);
                            Map<String, Operation> matching = new HashMap<>();
                            for (Map.Entry<String, Operation> entry : options.entrySet()) {
                                if (entry.getKey().startsWith(buffer.toString())) {
                                    matching.put(entry.getKey(), entry.getValue());
                                }
                            }
                            switch (matching.size()) {
                                case 0:
                                    buffer.setLength(0);
                                    break;
                                case 1:
                                    buffer.setLength(0);
                                    buffer.append(matching.keySet().iterator().next());
                                    break;
                            }
                        }
                    }
                    //
                    // Pattern edition
                    //
                    else if (buffer.length() > 0 && (buffer.charAt(0) == '/' || buffer.charAt(0) == '?')) {
                        int c = terminal.reader().read();
                        message = null;
                        if (c == '\r') {
                            try {
                                pattern = buffer.toString().substring(1);
                                getPattern();
                                if (buffer.charAt(0) == '/') {
                                    moveToNextMatch();
                                } else {
                                    moveToPreviousMatch();
                                }
                                buffer.setLength(0);
                            } catch (PatternSyntaxException e) {
                                String str = e.getMessage();
                                if (str.indexOf('\n') > 0) {
                                    str = str.substring(0, str.indexOf('\n'));
                                }
                                pattern = null;
                                buffer.setLength(0);
                                message = "Invalid pattern: " + str + " (Press a key)";
                                display(false);
                                terminal.reader().read();
                                message = null;
                            }
                        } else if (c == '\b') {
                            if (buffer.length() > 0) buffer.setLength(buffer.length() - 1);
                        } else {
                            buffer.append((char) c);
                        }
                    }
                    //
                    // Command reading
                    //
                    else {
                        Operation obj = bindingReader.readBinding(keys, null, false);
                        if (obj == Operation.CHAR) {
                            char c = bindingReader.getLastBinding().charAt(0);
                            // Enter option mode or pattern edit mode
                            if (c == '-' || c == '/' || c == '?') {
                                buffer.setLength(0);
                            }
                            buffer.append(c);
                        } else {
                            op = obj;
                        }
                    }
                    if (op != null) {
                        message = null;
                        switch (op) {
                            case FORWARD_ONE_LINE:
                                moveForward(getStrictPositiveNumberInBuffer(1));
                                break;
                            case BACKWARD_ONE_LINE:
                                moveBackward(getStrictPositiveNumberInBuffer(1));
                                break;
                            case FORWARD_ONE_WINDOW_OR_LINES:
                                moveForward(getStrictPositiveNumberInBuffer(window));
                                break;
                            case FORWARD_ONE_WINDOW_AND_SET:
                                window = getStrictPositiveNumberInBuffer(window);
                                moveForward(window);
                                break;
                            case FORWARD_ONE_WINDOW_NO_STOP:
                                moveForward(window);
                                // TODO: handle no stop
                                break;
                            case FORWARD_HALF_WINDOW_AND_SET:
                                halfWindow = getStrictPositiveNumberInBuffer(halfWindow);
                                moveForward(halfWindow);
                                break;
                            case BACKWARD_ONE_WINDOW_AND_SET:
                                window = getStrictPositiveNumberInBuffer(window);
                                moveBackward(window);
                                break;
                            case BACKWARD_ONE_WINDOW_OR_LINES:
                                moveBackward(getStrictPositiveNumberInBuffer(window));
                                break;
                            case BACKWARD_HALF_WINDOW_AND_SET:
                                halfWindow = getStrictPositiveNumberInBuffer(halfWindow);
                                moveBackward(halfWindow);
                                break;
                            case GO_TO_FIRST_LINE_OR_N:
                                // TODO: handle number
                                firstLineToDisplay = firstLineInMemory;
                                offsetInLine = 0;
                                break;
                            case GO_TO_LAST_LINE_OR_N:
                                // TODO: handle number
                                moveForward(Integer.MAX_VALUE);
                                break;
                            case LEFT_ONE_HALF_SCREEN:
                                firstColumnToDisplay = Math.max(0, firstColumnToDisplay - size.getColumns() / 2);
                                break;
                            case RIGHT_ONE_HALF_SCREEN:
                                firstColumnToDisplay += size.getColumns() / 2;
                                break;
                            case RIGHT_FRIST_COLUMN:
                                firstColumnToDisplay += Integer.MAX_VALUE;
                                break;
                            case LEFT_FRIST_COLUMN:
                                firstColumnToDisplay = 0;
                                break;
                            case REPEAT_SEARCH_BACKWARD:
                            case REPEAT_SEARCH_BACKWARD_SPAN_FILES:
                                moveToPreviousMatch();
                                break;
                            case REPEAT_SEARCH_FORWARD:
                            case REPEAT_SEARCH_FORWARD_SPAN_FILES:
                                moveToNextMatch();
                                break;
                            case UNDO_SEARCH:
                                pattern = null;
                                break;
                            case OPT_PRINT_LINES:
                                printLineNumbers = !printLineNumbers;
                                break;
                            case OPT_QUIET:
                                buffer.setLength(0);
                                quiet = !quiet;
                                veryQuiet = false;
                                message = quiet ? "Ring the bell for errors but not at eof/bof" : "Ring the bell for errors AND at eof/bof";
                                break;
                            case OPT_VERY_QUIET:
                                buffer.setLength(0);
                                veryQuiet = !veryQuiet;
                                quiet = false;
                                message = veryQuiet ? "Never ring the bell" : "Ring the bell for errors AND at eof/bof";
                                break;
                            case OPT_CHOP_LONG_LINES:
                                buffer.setLength(0);
                                offsetInLine = 0;
                                chopLongLines = !chopLongLines;
                                message = chopLongLines ? "Chop long lines" : "Fold long lines";
                                break;
                            case OPT_IGNORE_CASE_COND:
                                ignoreCaseCond = !ignoreCaseCond;
                                ignoreCaseAlways = false;
                                message = ignoreCaseCond ? "Ignore case in searches" : "Case is significant in searches";
                                break;
                            case OPT_IGNORE_CASE_ALWAYS:
                                ignoreCaseAlways = !ignoreCaseAlways;
                                ignoreCaseCond = false;
                                message = ignoreCaseAlways ? "Ignore case in searches and in patterns" : "Case is significant in searches";
                                break;
                            case NEXT_FILE:
                                if (sourceIdx < sources.size() - 1) {
                                    sourceIdx++;
                                    openSource();
                                } else {
                                    message = "No next file";
                                }
                                break;
                            case PREV_FILE:
                                if (sourceIdx > 0) {
                                    sourceIdx--;
                                    openSource();
                                } else {
                                    message = "No previous file";
                                }
                                break;
                            case EXIT:
                                continue;
                        }
                        buffer.setLength(0);
                    }
                    if (quitAtFirstEof && nbEof > 0 || quitAtSecondEof && nbEof > 1) {
                        if (sourceIdx < sources.size() - 1) {
                            sourceIdx++;
                            openSource();
                        } else {
                            op = Operation.EXIT;
                            continue;
                        }
                    }
                    display(false);
                } while (op != Operation.EXIT);
            } catch (InterruptedException ie) {
                // Do nothing
            } finally {
                terminal.setAttributes(attr);
                if (prevHandler != null) {
                    terminal.handle(Signal.WINCH, prevHandler);
                }
                // Use main buffer
                display.exit();
                if (!noKeypad) {
                    terminal.puts(Capability.keypad_local);
                }
                terminal.writer().flush();
            }
        } finally {
            lines = null;
            reader.close();
        }
    }

    protected void openSource() throws IOException {
        if (reader != null) {
            reader.close();
        }
        Source source = sources.get(sourceIdx);
        InputStream in = source.read();
        if (sources.size() == 1) {
            message = source.getName();
        } else {
            message = source.getName() + " (file " + (sourceIdx + 1) + " of " + sources.size() + ")";
        }
        reader = new BufferedReader(new InputStreamReader(new InterruptibleInputStream(in)));
        firstLineInMemory = 0;
        lines = new ArrayList<>();
        firstLineToDisplay = 0;
        firstColumnToDisplay = 0;
        offsetInLine = 0;
    }

    private void moveToNextMatch() throws IOException {
        Pattern compiled = getPattern();
        if (compiled != null) {
            for (int lineNumber = firstLineToDisplay + 1; ; lineNumber++) {
                AttributedString line = getLine(lineNumber);
                if (line == null) {
                    break;
                } else if (compiled.matcher(line).find()) {
                    firstLineToDisplay = lineNumber;
                    offsetInLine = 0;
                    return;
                }
            }
        }
        message = "Pattern not found";
    }

    private void moveToPreviousMatch() throws IOException {
        Pattern compiled = getPattern();
        if (compiled != null) {
            for (int lineNumber = firstLineToDisplay - 1; lineNumber >= firstLineInMemory; lineNumber--) {
                AttributedString line = getLine(lineNumber);
                if (line == null) {
                    break;
                } else if (compiled.matcher(line).find()) {
                    firstLineToDisplay = lineNumber;
                    offsetInLine = 0;
                    return;
                }
            }
        }
        message = "Pattern not found";
    }

    private String printable(String s) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c == ESCAPE) {
                sb.append("ESC");
            } else if (c < 32) {
                sb.append('^').append((char) (c + '@'));
            } else if (c < 128) {
                sb.append(c);
            } else {
                sb.append('\\').append(String.format("%03o", (int) c));
            }
        }
        return sb.toString();
    }

    void moveForward(int lines) throws IOException {
        int height = size.getRows();
        if (titleLines > 0 && lines > titleLines) lines -= titleLines;
        while (--lines >= 0) {
            int lastLineToDisplay = firstLineToDisplay;
            for (int l = 0; l < height - 1; l++) {
                AttributedString line = getLine(lastLineToDisplay);
                if (line == null) {
                    eof();
                    return;
                }
                lastLineToDisplay++;
            }
            ++firstLineToDisplay;
        }
    }

    void moveBackward(int lines) throws IOException {
        int height = size.getRows();
        if (titleLines > 0 && lines > titleLines) lines -= titleLines;
        while (--lines >= 0) {
            if (firstLineToDisplay <= firstLineInMemory) break;
            --firstLineToDisplay;
            int lastLineToDisplay = firstLineToDisplay;
            for (int l = 0; l < height - 1; l++) {
                AttributedString line = getLine(lastLineToDisplay);
                if (line == null) {
                    ++lines;
                    break;
                }
                lastLineToDisplay++;
            }
        }
    }

    private void eof() {
        nbEof++;
        if (sourceIdx < sources.size() - 1) {
            message = "(END) - Next: " + sources.get(sourceIdx + 1).getName();
        } else {
            message = "(END)";
        }
        if (!quiet && !veryQuiet && !quitAtFirstEof && !quitAtSecondEof) {
            terminal.puts(Capability.bell);
            terminal.writer().flush();
        }
    }

    private void bof() {
        if (!quiet && !veryQuiet) {
            terminal.puts(Capability.bell);
            terminal.writer().flush();
        }
    }

    int getStrictPositiveNumberInBuffer(int def) {
        try {
            int n = Integer.parseInt(buffer.toString());
            return (n > 0) ? n : def;
        } catch (NumberFormatException e) {
            return def;
        } finally {
            buffer.setLength(0);
        }
    }

    int lineIndex;
    private final static Pattern RTRIM = Pattern.compile("\\s+$");

    AttributedString getLine(int line) throws IOException {
        while (line >= lines.size()) {
            String str = reader.readLine();
            if (str != null) {
                AttributedString buff = AttributedString.fromAnsi(RTRIM.matcher(str).replaceAll(""), tabs);
                boolean found = false;
                for (int i = 0; i < titleLines; i++) {
                    if (titles[i] == null) {
                        titles[i] = buff;
                        found = true;
                        break;
                    }
                }
                if (!found) lines.add(buff);
            } else {
                break;
            }
        }
        lineIndex = -1;
        if (line - firstLineToDisplay < titleLines) return titles[line - firstLineToDisplay];
        else line -= titleLines;

        if (line < lines.size()) {
            lineIndex = line + 1;
            return lines.get(line);
        }
        return null;
    }

    int globalLineWidth = 0;

    synchronized boolean display(boolean oneScreen) throws IOException {
        if (!oneScreen) {
            if (System.getenv("IS_WSL") == null && !OSUtils.IS_MSYSTEM && !OSUtils.IS_CYGWIN) {
                if (terminal.reader().peek(128L) != NonBlockingReader.READ_EXPIRED) return false;
            } else {
                if (terminal.reader().available() <= 0) {
                    try {
                        Thread.sleep(128L);
                    } catch (InterruptedException e) {

                    }
                }
                if (terminal.reader().available() > 0) return false;
            }
        }

        List<AttributedString> newLines = new ArrayList<>();
        //-1 due to "/b" issue in org.jline.utils.Display
        int width = size.getColumns() - (printLineNumbers ? numWidth + 1 : 0) - 1;
        int height = size.getRows();
        int inputLine = firstLineToDisplay;
        int maxWidth = 0;
        AttributedStringBuilder asb = new AttributedStringBuilder();
        AttributedString curLine = null;
        Pattern compiled = getPattern();
        boolean fitOnOneScreen = false;
        if (globalLineWidth > 0 && firstColumnToDisplay > globalLineWidth - width / 2) {
            firstColumnToDisplay = Math.max(0, globalLineWidth - width / 2);
        }
        for (int terminalLine = 0; terminalLine < height - 1; terminalLine++) {
            if (curLine == null) {
                curLine = getLine(inputLine++);
                if (curLine == null) {
                    if (oneScreen) {
                        fitOnOneScreen = true;
                        break;
                    }
                    curLine = new AttributedString("");
                }
                if (compiled != null) {
                    curLine = curLine.styleMatches(compiled, AttributedStyle.DEFAULT.inverse());
                }
                if (printLineNumbers && padding > 0) curLine = curLine.columnSubSequence(padding, Integer.MAX_VALUE);
                maxWidth = Math.max(maxWidth, curLine.length());
            }
            AttributedString toDisplay;
            if (firstColumnToDisplay > 0 || chopLongLines) {
                int off = firstColumnToDisplay;
                if (terminalLine == 0 && offsetInLine > 0) {
                    off = Math.max(offsetInLine, off);
                }
                if (padding > 0 && off > padding && !printLineNumbers) {
                    asb.setLength(0);
                    asb.append(String.join("", Collections.nCopies(padding, " ")));
                    asb.append(curLine.columnSubSequence(off, off + width - padding));
                    toDisplay = asb.toAttributedString();
                } else toDisplay = curLine.columnSubSequence(off, off + width);
                curLine = null;
            } else {
                if (terminalLine == 0 && offsetInLine > 0) {
                    curLine = curLine.columnSubSequence(offsetInLine, Integer.MAX_VALUE);
                }
                toDisplay = curLine.columnSubSequence(0, width);
                curLine = curLine.columnSubSequence(width, Integer.MAX_VALUE);
                if (curLine.length() == 0) {
                    curLine = null;
                }
            }

            if (printLineNumbers) {
                asb.setLength(0);
                if (lineIndex == -1) asb.append(String.join("", Collections.nCopies(numWidth, " "))).append("|");
                else asb.append(String.format("%" + numWidth + "d|", lineIndex));
                asb.append(toDisplay);
                newLines.add(asb.toAttributedString());
            } else {
                newLines.add(toDisplay);
            }
        }

        if (oneScreen) {
            if (fitOnOneScreen && maxWidth <= width) {
                newLines.forEach(l -> l.println(terminal));
                terminal.writer().flush();
                return true;
            }
            return false;
        }

        globalLineWidth = Math.max(maxWidth, globalLineWidth);
        AttributedStringBuilder msg = new AttributedStringBuilder();
        if (buffer.length() > 0) {
            msg.append(" ").append(buffer);
        } else if (bindingReader.getCurrentBuffer().length() > 0 && terminal.reader().available() == 0) {
            msg.append(" ").append(printable(bindingReader.getCurrentBuffer()));
        } else if (message != null) {
            msg.style(AttributedStyle.INVERSE);
            msg.append(message);
            msg.style(AttributedStyle.INVERSE.inverseOff());
        } else {
            msg.append(":");
        }
        newLines.add(msg.toAttributedString());
        //display.setDelayLineWrap(false);

        display.update(newLines, -1);
        return false;
    }

    private Pattern getPattern() {
        Pattern compiled = null;
        if (pattern != null) {
            boolean insensitive = ignoreCaseAlways || ignoreCaseCond && pattern.toLowerCase().equals(pattern);
            compiled = Pattern.compile("(" + pattern + ")", insensitive ? Pattern.CASE_INSENSITIVE | Pattern.UNICODE_CASE : 0);
        }
        return compiled;
    }


    /**
     * This is for long running commands to be interrupted by ctrl-c
     *
     * @throws InterruptedException if the thread has been interruped
     */
    public static void checkInterrupted() throws InterruptedException {
        Thread.yield();
        if (Thread.currentThread().isInterrupted()) {
            throw new InterruptedException();
        }
    }

    private void bindKeys(KeyMap<Operation> map) {
        map.bind(Operation.HELP, "h", "H");
        map.bind(Operation.EXIT, "q", ":q", "Q", ":Q", "ZZ");
        map.bind(Operation.FORWARD_ONE_LINE, "e", ctrl('E'), "j", ctrl('N'), "\r", key(terminal, Capability.key_down));
        map.bind(Operation.BACKWARD_ONE_LINE, "y", ctrl('Y'), "k", ctrl('K'), ctrl('P'), key(terminal, Capability.key_up));
        map.bind(Operation.FORWARD_ONE_WINDOW_OR_LINES, "f", ctrl('F'), ctrl('V'), " ");
        map.bind(Operation.BACKWARD_ONE_WINDOW_OR_LINES, "b", ctrl('B'), alt('v'));
        map.bind(Operation.FORWARD_ONE_WINDOW_AND_SET, "z");
        map.bind(Operation.BACKWARD_ONE_WINDOW_AND_SET, "w");
        map.bind(Operation.FORWARD_ONE_WINDOW_NO_STOP, alt(' '));
        map.bind(Operation.FORWARD_HALF_WINDOW_AND_SET, "d", ctrl('D'));
        map.bind(Operation.BACKWARD_HALF_WINDOW_AND_SET, "u", ctrl('U'));
        map.bind(Operation.RIGHT_ONE_HALF_SCREEN, alt(')'), key(terminal, Capability.key_right));
        map.bind(Operation.LEFT_ONE_HALF_SCREEN, alt('('), key(terminal, Capability.key_left));
        map.bind(Operation.RIGHT_FRIST_COLUMN, key(terminal, Capability.key_end), "]");
        map.bind(Operation.LEFT_FRIST_COLUMN, key(terminal, Capability.key_home), "[");
        map.bind(Operation.FORWARD_FOREVER, "F");
        map.bind(Operation.REPEAT_SEARCH_FORWARD, "n", alt('n'));
        map.bind(Operation.REPEAT_SEARCH_BACKWARD, "N", ctrl('N'));
        map.bind(Operation.UNDO_SEARCH, alt('u'));
        map.bind(Operation.GO_TO_FIRST_LINE_OR_N, "g", "<", alt('<'));
        map.bind(Operation.GO_TO_LAST_LINE_OR_N, "G", ">", alt('>'));
        map.bind(Operation.NEXT_FILE, ":n");
        map.bind(Operation.PREV_FILE, ":p");
        map.bind(Operation.OPT_PRINT_LINES, "l", "L");
        "-/0123456789?".chars().forEach(c -> map.bind(Operation.CHAR, Character.toString((char) c)));
    }

    protected enum Operation {

        // General
        HELP,
        EXIT,

        // Moving
        FORWARD_ONE_LINE,
        BACKWARD_ONE_LINE,
        FORWARD_ONE_WINDOW_OR_LINES,
        BACKWARD_ONE_WINDOW_OR_LINES,
        FORWARD_ONE_WINDOW_AND_SET,
        BACKWARD_ONE_WINDOW_AND_SET,
        FORWARD_ONE_WINDOW_NO_STOP,
        FORWARD_HALF_WINDOW_AND_SET,
        BACKWARD_HALF_WINDOW_AND_SET,
        LEFT_ONE_HALF_SCREEN,
        RIGHT_ONE_HALF_SCREEN,
        LEFT_FRIST_COLUMN,
        RIGHT_FRIST_COLUMN,
        FORWARD_FOREVER,
        REPAINT,
        REPAINT_AND_DISCARD,

        // Searching
        REPEAT_SEARCH_FORWARD,
        REPEAT_SEARCH_BACKWARD,
        REPEAT_SEARCH_FORWARD_SPAN_FILES,
        REPEAT_SEARCH_BACKWARD_SPAN_FILES,
        UNDO_SEARCH,

        // Jumping
        GO_TO_FIRST_LINE_OR_N,
        GO_TO_LAST_LINE_OR_N,
        GO_TO_PERCENT_OR_N,
        GO_TO_NEXT_TAG,
        GO_TO_PREVIOUS_TAG,
        FIND_CLOSE_BRACKET,
        FIND_OPEN_BRACKET,

        // Options
        OPT_PRINT_LINES,
        OPT_CHOP_LONG_LINES,
        OPT_QUIT_AT_FIRST_EOF,
        OPT_QUIT_AT_SECOND_EOF,
        OPT_QUIET,
        OPT_VERY_QUIET,
        OPT_IGNORE_CASE_COND,
        OPT_IGNORE_CASE_ALWAYS,

        // Files
        NEXT_FILE,
        PREV_FILE,

        // 
        CHAR,
        OPT_SHOW_LINE_NUM

    }

    static class InterruptibleInputStream extends FilterInputStream {
        InterruptibleInputStream(InputStream in) {
            super(in);
        }

        @Override
        public int read(byte[] b, int off, int len) throws IOException {
            if (Thread.currentThread().isInterrupted()) {
                throw new InterruptedIOException();
            }
            return super.read(b, off, len);
        }
    }

    static class Play extends Display {
        public Play(Terminal terminal) {
            super(terminal, true);
        }

        boolean isStarted;
        boolean isEnterCA;

        public void init(boolean isEnterCA) {
            reset();
            isStarted = false;
            this.isEnterCA = isEnterCA;
            if (this.isEnterCA) terminal.puts(Capability.enter_ca_mode);
        }

        public void exit() {
            if (this.isEnterCA) terminal.puts(Capability.exit_ca_mode);
        }

        @Override
        public synchronized void update(List<AttributedString> newLines, int targetCursorPos) {
            if (isStarted) {
                clear();
                if (!isEnterCA) {
                    terminal.puts(Capability.enter_ca_mode);
                    isEnterCA = true;
                }
            } else {
                isStarted = true;
                if (OSUtils.IS_CONEMU || "terminator".equals(System.getenv("TERM")) || "ansicon".equals(System.getenv("ANSICON_DEF"))) {
                    clear();
                } else {
                    cursorPos = 0;
                    oldLines.clear();
                }
            }
            Size size = terminal.getSize();
            super.resize(size.getRows(), size.getColumns());
            super.update(newLines, targetCursorPos, false);
            terminal.writer().flush();
        }
    }
}
