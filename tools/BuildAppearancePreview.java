import com.jpexs.decompiler.flash.SWF;
import com.jpexs.decompiler.flash.abc.ABC;
import com.jpexs.decompiler.flash.abc.ScriptPack;
import com.jpexs.decompiler.flash.abc.avm2.parser.script.AbcIndexing;
import com.jpexs.decompiler.flash.abc.avm2.parser.script.ActionScript3Parser;
import com.jpexs.decompiler.flash.importers.FFDecAs3ScriptReplacer;
import com.jpexs.decompiler.flash.tags.ABCContainerTag;
import com.jpexs.decompiler.flash.tags.Tag;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

/** Builds a separate Preview SWF from the source files in swf-src. */
public class BuildAppearancePreview {
    private static final String APPEARANCE = "mico.appearance.MicoAppearanceImages";

    public static void main(String[] args) throws Exception {
        if (args.length != 3) {
            throw new IllegalArgumentException("Use: BuildAppearancePreview.java <original.swf> <preview.swf> <swf-src>");
        }
        Path input = Path.of(args[0]);
        Path output = Path.of(args[1]).toAbsolutePath().normalize();
        Path source = Path.of(args[2]);
        if (Files.exists(output)) {
            throw new IllegalArgumentException("Escolha um novo arquivo de saída: " + output);
        }
        SWF swf;
        try (InputStream in = Files.newInputStream(input)) {
            swf = new SWF(in, false);
        }

        List<ABC> abcs = new ArrayList<>();
        for (ABCContainerTag tag : swf.getAbcList()) {
            abcs.add(tag.getABC());
        }
        ScriptPack client = find(abcs, "AJClient");
        if (client == null || find(abcs, "gui.MySettings") == null || find(abcs, "avatar.NameBar") == null) {
            throw new IllegalArgumentException("O SWF não contém as classes do Mico esperadas.");
        }
        if (find(abcs, APPEARANCE) != null) {
            throw new IllegalArgumentException("O SWF de entrada já contém o editor de imagens.");
        }
        AbcIndexing index = swf.getAbcIndex();
        if (SWF.getPlayerGlobalAbcIndex() == null) {
            throw new IllegalStateException("Configure a biblioteca playerglobal no JPEXS antes de compilar.");
        }

        index.selectAbc(client.abc);
        String appearance = Files.readString(source.resolve("MicoAppearanceImages.as"));
        new ActionScript3Parser(index).addScript(appearance, APPEARANCE.replace('.', '/'), 0, 0, swf.getDocumentClass(), client.abc);
        ((Tag) client.abc.parentTag).setModified(true);
        swf.clearAllCache();
        replace(abcs, "avatar.NameBar", source.resolve("NameBar.as"));
        replace(abcs, "gui.itemWindows.ItemWindowToggle", source.resolve("ItemWindowToggle.as"));
        replace(abcs, "gui.MySettings", source.resolve("MySettings.as"));
        swf.setModified(true);

        Path temporary = Files.createTempFile(output.getParent(), "mico-appearance-", ".swf.tmp");
        try {
            try (OutputStream out = Files.newOutputStream(temporary)) {
                swf.saveTo(out);
            }
            Files.move(temporary, output);
        } finally {
            Files.deleteIfExists(temporary);
        }
        System.out.println("Cópia do Preview compilada em " + output);
    }

    private static ScriptPack find(List<ABC> abcs, String name) {
        for (ABC abc : abcs) {
            ScriptPack pack = abc.findScriptPackByPath(name, abcs);
            if (pack != null) {
                return pack;
            }
        }
        return null;
    }

    private static void replace(List<ABC> abcs, String name, Path file) throws Exception {
        ScriptPack pack = find(abcs, name);
        if (pack == null || !pack.abc.replaceScriptPack(new FFDecAs3ScriptReplacer(false), pack, Files.readString(file), List.of())) {
            throw new IllegalStateException("Falha ao compilar " + name);
        }
        ((Tag) pack.abc.parentTag).setModified(true);
        System.out.println("Classe compilada: " + name);
    }
}
