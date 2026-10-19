import java.io.*;
import java.util.*;
import com.adobe.flash.compiler.fxg.*;
import com.adobe.flash.compiler.fxg.flex.FXGSymbolClass;
import com.adobe.flash.compiler.fxg.swf.FXG2SWFTranscoder;
import com.adobe.flash.compiler.problems.ICompilerProblem;
import com.adobe.flash.swf.*;
import com.adobe.flash.swf.io.SWFWriter;
import com.adobe.flash.swf.tags.*;
import com.adobe.flash.swf.types.*;

/** Use the installed AIR SDK's own FXG path-to-SWF transcoder. */
public final class VectorIconCompiler {
    private static void add(SWFFrame frame, ICharacterTag tag, Set<ICharacterTag> seen) {
        if (!seen.add(tag)) return;
        if (tag instanceof ICharacterReferrer)
            for (ICharacterTag child : ((ICharacterReferrer)tag).getReferences()) add(frame, child, seen);
        frame.addTag(tag);
    }
    public static void main(String[] args) throws Exception {
        SWF swf = new SWF(); swf.setVersion(19); swf.setUseAS3(true);
        swf.setFrameSize(new Rect(10240,10240)); swf.setFrameRate(30);
        swf.setBackgroundColor(new RGB(0xffffff));
        SWFFrame frame = new SWFFrame();
        Set<ICharacterTag> seen = Collections.newSetFromMap(new IdentityHashMap<>());
        for (int i=1; i<args.length; i++) {
            File source = new File(args[i]);
            String name = source.getName().replace(".fxg", "");
            List<ICompilerProblem> problems = new ArrayList<>();
            FXGSymbolClass symbol;
            try (Reader reader = new FileReader(source)) {
                var node = FXGParserFactory.createDefaultParser().parse(reader, source.toString(), problems);
                symbol = new FXG2SWFTranscoder().transcode(node, "", name, new HashMap<>(), problems);
            }
            if (!problems.isEmpty()) throw new IllegalStateException(problems.toString());
            add(frame, symbol.getSymbol(), seen);
            frame.defineSymbol(symbol.getSymbol(), name);
        }
        swf.addFrame(frame);
        try (SWFWriter writer = new SWFWriter(swf, Header.Compression.ZLIB)) {
            writer.writeTo(new File(args[0]));
        }
        System.out.println("VECTOR_ICON_LIBRARY " + args[0] + " symbols=" + (args.length-1));
    }
}
