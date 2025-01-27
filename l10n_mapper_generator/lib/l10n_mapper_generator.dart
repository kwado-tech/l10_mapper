import 'dart:async';

import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

export 'l10n_mapper_builder.dart';

// indicates methods mapper would not be generated for
const genExceptions = [
  'of',
  'delegate',
  'localizationsDelegates',
  'supportedLocales',
];

class L10nMapperGenerator extends Generator {
  final bool l10n;
  final bool locale;
  final bool parseL10n;
  List<String> classNames;

  //? optional and default: null. should be parsed if translation should not return
  //? nullable values when key is not found but will return specified error message instead
  final String? message;

  L10nMapperGenerator({required this.l10n, required this.locale, required this.parseL10n, required this.message, this.classNames = const []});

  @override
  FutureOr<String?> generate(LibraryReader library, BuildStep buildStep) {
    if (classNames.isEmpty) {
      classNames.add('AppLocalizations');
    }

    final buffer = StringBuffer();

    for (var classElement in library.classes.where((c) => c.isAbstract)) {
      if (classNames.contains(classElement.displayName)) {
        final className = classElement.displayName;
        final localizationPath = classElement.source.uri;
        final mapperName = '${className}Mapper';
        final appLocalizationsExtensionName = '${className}Extension';
        final buildContextExtensionName = 'BuildContextExtension';

        final nullable = message == null;
        final shouldGenerateExtensions = l10n || locale || parseL10n;

        // import
        buffer.writeln("import '$localizationPath';");
        buffer.writeln("import 'package:flutter/widgets.dart';");

        // generate extensions
        if (shouldGenerateExtensions) {
          final bufferBuildContextExtension = StringBuffer();
          final bufferAppLocalizationsExtension = StringBuffer();
          final bufferL10nHelper = StringBuffer();

          bufferBuildContextExtension.writeln('extension $buildContextExtensionName on BuildContext {');
          bufferAppLocalizationsExtension.writeln('extension $appLocalizationsExtensionName on $className {');

          bufferBuildContextExtension.writeln('  $className get _localizations => $className.of(this)!;');

          if (l10n) {
            bufferBuildContextExtension.writeln('$className get l10n => _localizations;');
          }

          if (locale) {
            bufferBuildContextExtension.writeln('Locale get locale => Localizations.localeOf(this);');
          }

          if (parseL10n) {
            bufferBuildContextExtension.writeln(
                "${nullable ? 'String?' : 'String'} parseL10n(String translationKey, {List<Object>? arguments}) {");
            bufferAppLocalizationsExtension.writeln(
                "${nullable ? 'String?' : 'String'} parseL10n(String translationKey, {List<Object>? arguments}) {");

            bufferBuildContextExtension.writeln('final localizations = $className.of(this)!;');
            bufferBuildContextExtension.writeln('return L10nHelper.parseL10n(localizations, translationKey, arguments: arguments);');
            bufferAppLocalizationsExtension.writeln('return L10nHelper.parseL10n(this, translationKey, arguments: arguments);');

            bufferBuildContextExtension.writeln('}');
            bufferAppLocalizationsExtension.writeln('}');

            bufferL10nHelper.writeln('class L10nHelper {');
            bufferL10nHelper.writeln('static String parseL10n($className localizations, String translationKey, {List<Object>? arguments}) {');

            bufferL10nHelper.writeln('const mapper = $mapperName();');
            bufferL10nHelper.writeln('final object = mapper.toLocalizationMap(localizations)[translationKey];');

            // account for null-case
            if (!nullable) {
              bufferL10nHelper.writeln("if (object == null) return '$message';");

              bufferL10nHelper.writeln('if (object is String) return object;');
            } else {
              bufferL10nHelper.writeln('if (object is String || object == null) return object;');
            }

            bufferL10nHelper.writeln("assert(arguments != null, 'Arguments should not be null!');");
            bufferL10nHelper.writeln("assert(arguments!.isNotEmpty, 'Arguments should not be empty!');");

            bufferL10nHelper.writeln('return Function.apply(object, arguments);');
            bufferL10nHelper.writeln('}');

            bufferL10nHelper.writeln('}');
          }

          bufferBuildContextExtension.writeln('}');
          bufferAppLocalizationsExtension.writeln('}');

          buffer
            ..write(bufferBuildContextExtension.toString())
            ..write(bufferAppLocalizationsExtension.toString())
            ..write(bufferL10nHelper.toString());
        }


        // end of extension

        // generate class
        buffer.writeln('class $mapperName {');

        // constructor
        buffer.writeln('const $mapperName();');

        // toLocalizationMap
        buffer.writeln('Map<String, dynamic> toLocalizationMap($className localizations) {');

        buffer.writeln('return {');
        // all getters
        for (final field in classElement.fields) {
          final name = field.name;

          // skips gen-exceptions
          if (genExceptions.contains(name)) continue;

          buffer.writeln("'$name': localizations.$name,");
        }

        // all methods
        for (final method in classElement.methods) {
          final name = method.name;

          // skips gen-exceptions
          if (genExceptions.contains(name)) continue;
          final parameters = method.parameters.map((e) => e.name).join(', ');

          buffer.writeln("'$name': ($parameters) => localizations.$name($parameters),");
        }

        buffer.writeln('};');
        buffer.writeln('}');
        buffer.writeln('}');

        return buffer.toString();
      }
    }

    return super.generate(library, buildStep);
  }
}