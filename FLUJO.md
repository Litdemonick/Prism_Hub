# Flujo de trabajo — PrismHub

Acuerdos de cómo se trabaja en este proyecto. No es documentación del código:
es el procedimiento a seguir en cada sesión.

## 1. Antes de tocar, medir

Nada se cambia por deducción. Si algo falla, primero se busca la causa con
datos —un log, una petición real, leer el código del camino completo— y recién
después se toca.

Esto salió de haber perdido varias rondas encadenando hipótesis: la búsqueda de
XVideos en Android, la pantalla gris del arranque y las extensiones marcadas
inestables se resolvieron los tres cuando apareció el dato, no antes.

Si no se puede medir en el momento, se dice y se pide el dato en vez de
adivinar.

## 2. Commit cada ~4 cambios, sin push

Cada cuatro mejoras, funciones nuevas o correcciones se hace **commit local**.
Nunca `push` sin que el usuario lo pida.

- El commit local guarda el trabajo y permite volver atrás sin perder nada.
- El push es visible para todos, y eso lo decide el usuario.
- **Excepción: prism-plus.** Las extensiones se pushean apenas están
  verificadas, sin esperar confirmación — el usuario las necesita publicadas
  para recibirlas en el app.

El mensaje de commit explica **por qué**, no solo qué. Si el cambio arregla
algo, se cuenta cuál era el síntoma y cuál la causa real.

## 3. Verificación mínima antes de dar algo por hecho

1. `dart analyze lib/` sin errores ni warnings.
2. `flutter build windows --debug` compila.

**El APK lo compila y prueba el usuario.** No se corre `flutter build apk`.

Si algo no se pudo verificar, se dice explícitamente en vez de darlo por bueno.

## 4. Las tres plataformas, siempre

Todo cambio tiene que funcionar en **Windows, Linux y Android**. Trampas ya
conocidas de este proyecto:

- **Navegación:** en Android la raíz es `GetMaterialApp` y go_router NO está
  montado; en escritorio es al revés con `Get.to`. Y un `Get.to` anidado dentro
  de otra página abierta con `Get.to` no navega — ahí va `Navigator.push`.
- **Árbol de widgets:** en escritorio la raíz es `FluentApp`: no hay `Theme` de
  Material (`Theme.of` cae al tema CLARO) ni `Material` ancestro. Y en Android
  no hay `FluentTheme` ni `FluentLocalizations`, así que los widgets de fluent
  revientan.
- **Diálogos:** `RouterUtils.pop` no cierra los abiertos con
  `fluent.showDialog`; ahí va `Navigator.of(ctx).pop()`.
- **Scroll:** el `AlertDialog` de Android ya desplaza su contenido; agregarle
  otro scroll adentro lo recorta.

## 5. Mantener al día el aviso de beta

`lib/views/widgets/beta_notice.dart` le cuenta al usuario nuevo qué esperar.
**Cuando algo de lo que promete se cumple, hay que actualizarlo**, o el aviso
empieza a mentir:

- Bloqueador de anuncios → cuando exista, cambiar el texto de "va a llegar" a
  cómo se usa y dónde se apaga.
- Funciones a medias y opciones bloqueadas → si se habilitan, sacarlas del
  aviso.
- Linux poco probado → cuando se pruebe de verdad, quitar ese punto.
- El número de extensiones sale del índice real, ese no hay que tocarlo.

El aviso se muestra una sola vez por instalación y guarda **en qué versión** se
aceptó, así que si algún día conviene volver a mostrarlo, alcanza con comparar.

## 6. Comentar el porqué, no el qué

Los comentarios explican la decisión y qué pasaba antes, para que nadie
"arregle" algo que ya está resuelto. El código dice qué hace; el comentario
dice por qué así y no de la forma obvia.

## 7. Decisiones acordadas van a memoria

Cuando se decide algo que condiciona el resto del trabajo —un criterio, un
umbral, una regla de negocio— se anota en la memoria del proyecto con el
motivo. Las que ya están: los estados de seguimiento, el orden de "Continuar",
qué contenido lleva estados, y estos acuerdos.

## 8. Lo pendiente se dice, no se esconde

Si algo queda a medias, sin probar o sin hacer, se enumera al cerrar. Vale más
una lista honesta de pendientes que dar por terminado algo que no lo está.
