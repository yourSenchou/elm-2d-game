module Game.TwoD.Render
    exposing
        ( Renderable
        , BasicShape
        , rectangle
        , triangle
        , circle
        , ring
        , shape
        , shapeZ
        , shapeWithOptions
        , sprite
        , spriteZ
        , spriteWithOptions
        , animatedSprite
        , animatedSpriteZ
        , animatedSpriteWithOptions
        , customFragment
        , veryCustom
        , MakeUniformsFunc
        , parallaxScroll
        , parallaxScrollWithOptions
        , toWebGl
        , renderTransparent
        )

{-|
# 2D rendering module
This module provides a way to render commonly used objects in 2d games
like simple sprites and sprite animations.

It also provides colored shapes which can be great during prototyping.
The simple shapes can easily be replaced by nicer looking textures later.

suggested import:

    import Game.TwoD.Render as Render exposing (Renderable)


Most functions to render something come in 3 forms:

    thing, thingZ, thingWithOptions

The first is the most common one where you can specify
the size, the position in 2d and some more.


The second one is the same as the first, but with a 3d position.
The z position goes from -1 to 1, everything outside this will be invisible.
This can be used to put something in front or behind regardless of the render order.


The last one gives you all possible options, e.g. the rotation
, the pivot point of the rotation (normalized from 0 to 1), etc.

TODO: insert picture to visualize coordinate system.

@docs Renderable

## Basic Shapes
@docs BasicShape, rectangle, triangle, circle, ring

## Shapes
@docs shape
@docs shapeZ
@docs shapeWithOptions

### With texture

Textures are `Maybe` values because you can never have a texture at the start of your game.
You first have to load your textures. In case you pass a `Nothing` as a value for a texture,
A gray rectangle will be displayed instead.

For loading textures I suggest using the [game-resources library](http://package.elm-lang.org/packages/Zinggi/elm-game-resources/latest).

**NOTE**: Texture dimensions have to be in a power of 2, e.g. (2^n)x(2^m), like 4x16, 16x16, 512x256, etc.
If you try to use a non power of two texture, WebGL will spit out a bunch of warnings and display a black rectangle.

@docs sprite
@docs spriteZ
@docs spriteWithOptions

### Animated
@docs animatedSprite
@docs animatedSpriteZ
@docs animatedSpriteWithOptions

### Background
@docs parallaxScroll
@docs parallaxScrollWithOptions

## Custom
These are useful if you want to write your own GLSL shaders.
When writing your own shaders, you might want to look at
Game.TwoD.Shaders and Game.TwoD.Shapes for reusable parts.


@docs customFragment
@docs MakeUniformsFunc
@docs veryCustom
@docs renderTransparent
@docs toWebGl
-}

import Color exposing (Color)
import WebGL exposing (Texture)
import WebGL.Settings.Blend as Blend
import WebGL.Settings
import Math.Matrix4 exposing (Mat4)
import Math.Vector2 as V2 exposing (Vec2, vec2)
import Math.Vector3 as V3 exposing (Vec3)
import Game.TwoD.Shaders exposing (..)
import Game.TwoD.Shapes exposing (unitSquare, unitTriangle)
import Game.TwoD.Camera as Camera exposing (Camera)
import Game.Helpers as Helpers exposing (..)


{-|
A representation of something that can be rendered.
To actually render a `Renderable` onto a web page use the `Game.TwoD.*` functions
-}
type Renderable
    = ColoredShape { shape : BasicShape, transform : Mat4, color : Vec3 }
    | TexturedRectangle { transform : Mat4, texture : Texture, tileWH : Vec2 }
    | AnimatedSprite { transform : Mat4, texture : Texture, bottomLeft : Vec2, topRight : Vec2, duration : Float, numberOfFrames : Int }
    | ParallaxScroll { texture : Texture, tileWH : Vec2, scrollSpeed : Vec2, z : Float, offset : Vec2 }
    | Custom ({ cameraProj : Mat4, time : Float } -> WebGL.Entity)


{-|
A representation of a basic shape to use when rendering a ColoredShape
-}
type BasicShape
    = Rectangle
    | Triangle
    | Circle
    | Ring


{-| BasicShape constructor for a rectangle
-}
rectangle : BasicShape
rectangle =
    Rectangle


{-| BasicShape constructor for a triangle
-}
triangle : BasicShape
triangle =
    Triangle


{-| BasicShape constructor for a circle
-}
circle : BasicShape
circle =
    Circle


{-| BasicShape constructor for a ring
-}
ring : BasicShape
ring =
    Ring


{-|
Converts a Renderable to a WebGL.Entity.
You don't need this unless you want to slowely introduce
this library in a project that currently uses WebGL directly.

    toWebGl time camera (w, h) cameraProj renderable
-}
toWebGl : Float -> Camera -> Float2 -> Mat4 -> Renderable -> WebGL.Entity
toWebGl time camera screenSize cameraProj object =
    case object of
        ColoredShape { shape, transform, color } ->
            shapeToWebGl shape transform cameraProj color

        TexturedRectangle { transform, texture, tileWH } ->
            renderTransparent vertTexturedRect
                fragTextured
                unitSquare
                { transform = transform, texture = texture, cameraProj = cameraProj, tileWH = tileWH }

        AnimatedSprite { transform, texture, bottomLeft, topRight, duration, numberOfFrames } ->
            renderTransparent vertTexturedRect
                fragAnimTextured
                unitSquare
                { transform = transform, texture = texture, cameraProj = cameraProj, bottomLeft = bottomLeft, topRight = topRight, duration = duration, time = time, numberOfFrames = numberOfFrames }

        ParallaxScroll { texture, tileWH, scrollSpeed, z, offset } ->
            let
                size =
                    Camera.getViewSize screenSize camera

                pos =
                    Camera.getPosition camera
            in
                renderTransparent vertParallaxScroll
                    fragTextured
                    unitSquare
                    { texture = texture, tileWH = tileWH, scrollSpeed = scrollSpeed, z = z, offset = offset, cameraPos = V2.fromTuple pos, cameraSize = V2.fromTuple size }

        Custom f ->
            f { cameraProj = cameraProj, time = time }


{-|
This takes a BasicShape Renderable and converts it to a WebGL.Entity.
-}
shapeToWebGl : BasicShape -> Mat4 -> Mat4 -> Vec3 -> WebGL.Entity
shapeToWebGl shape transform cameraProj color =
    case shape of
        Rectangle ->
            renderTransparent vertColoredShape
                fragUniColor
                unitSquare
                { transform = transform, color = color, cameraProj = cameraProj }

        Triangle ->
            renderTransparent vertColoredShape
                fragUniColor
                unitTriangle
                { transform = transform, color = color, cameraProj = cameraProj }

        Circle ->
            renderTransparent vertColoredShape
                fragUniColorCircle
                unitSquare
                { transform = transform, color = color, cameraProj = cameraProj }

        Ring ->
            renderTransparent vertColoredShape
                fragUniColorRing
                unitSquare
                { transform = transform, color = color, cameraProj = cameraProj }


{-| This can be used inside `veryCustom` instead of `WebGL.entity`.
It's a custamized blend function that works well with textures with alpha.
-}
renderTransparent : WebGL.Shader attributes uniforms varyings -> WebGL.Shader {} uniforms varyings -> WebGL.Mesh attributes -> uniforms -> WebGL.Entity
renderTransparent =
    WebGL.entityWith
        [ Blend.custom
            { r = 0
            , g = 0
            , b = 0
            , a = 0
            , color = Blend.customAdd Blend.srcAlpha Blend.oneMinusSrcAlpha
            , alpha = Blend.customAdd Blend.one Blend.oneMinusSrcAlpha
            }
        ]


{-|
A colored shape, great for prototyping
-}
shape : BasicShape -> { o | color : Color, position : Float2, size : Float2 } -> Renderable
shape shape { size, position, color } =
    let
        ( x, y ) =
            position
    in
        shapeZ shape { size = size, position = ( x, y, 0 ), color = color }


{-|
The same, but with 3d position.
-}
shapeZ : BasicShape -> { o | color : Color, position : Float3, size : Float2 } -> Renderable
shapeZ shape { color, position, size } =
    shapeWithOptions
        shape
        { color = color, position = position, size = size, rotation = 0, pivot = ( 0, 0 ) }


{-|
A colored shape, that can also be rotated
-}
shapeWithOptions :
    BasicShape
    -> { o | color : Color, position : Float3, size : Float2, rotation : Float, pivot : Float2 }
    -> Renderable
shapeWithOptions shape { color, rotation, position, size, pivot } =
    let
        ( ( px, py ), ( w, h ), ( x, y, z ) ) =
            ( pivot, size, position )
    in
        ColoredShape
            { shape = shape
            , transform = makeTransform ( x, y, z ) rotation ( w, h ) ( px, py )
            , color = colorToRGBVector color
            }


{-|
A sprite.
-}
sprite : { o | texture : Maybe Texture, position : Float2, size : Float2 } -> Renderable
sprite { texture, position, size } =
    let
        ( x, y ) =
            position
    in
        spriteZ { texture = texture, position = ( x, y, 0 ), size = size }


{-|
A sprite with 3d position
-}
spriteZ : { o | texture : Maybe Texture, position : Float3, size : Float2 } -> Renderable
spriteZ { texture, position, size } =
    spriteWithOptions
        { texture = texture, position = position, size = size, tiling = ( 1, 1 ), rotation = 0, pivot = ( 0, 0 ) }


{-|
A sprite with tiling and rotation.

    spriteWithOptions {config | tiling = (3,5)}

will create a sprite with a texture that repeats itself 3 times horizontally and 5 times vertically.
TODO: picture!
-}
spriteWithOptions :
    { o | texture : Maybe Texture, position : Float3, size : Float2, tiling : Float2, rotation : Float, pivot : Float2 }
    -> Renderable
spriteWithOptions ({ texture, position, size, tiling, rotation, pivot } as args) =
    let
        ( ( w, h ), ( x, y, z ), ( px, py ), ( tw, th ) ) =
            ( size, position, pivot, tiling )
    in
        case texture of
            Just t ->
                TexturedRectangle
                    { transform = makeTransform ( x, y, z ) (rotation) ( w, h ) ( px, py )
                    , texture = t
                    , tileWH = vec2 tw th
                    }

            Nothing ->
                shapeZ Rectangle { position = position, size = size, color = Color.grey }


{-|
An animated sprite. `bottomLeft` and `topRight` define a sub area from a texture
where the animation frames are located. It's a normalized coordinate from 0 to 1.

TODO: picture!
-}
animatedSprite :
    { o
        | texture : Maybe Texture
        , position : Float2
        , size : Float2
        , bottomLeft : Float2
        , topRight : Float2
        , numberOfFrames : Int
        , duration : Float
    }
    -> Renderable
animatedSprite ({ position } as options) =
    let
        ( x, y ) =
            position
    in
        animatedSpriteZ { options | position = ( x, y, 0 ) }


{-|
The same with 3d position
-}
animatedSpriteZ :
    { o
        | texture : Maybe Texture
        , position : Float3
        , size : Float2
        , bottomLeft : Float2
        , topRight : Float2
        , numberOfFrames : Int
        , duration : Float
    }
    -> Renderable
animatedSpriteZ { texture, duration, numberOfFrames, position, size, bottomLeft, topRight } =
    animatedSpriteWithOptions
        { texture = texture
        , position = position
        , size = size
        , bottomLeft = bottomLeft
        , topRight = topRight
        , duration = duration
        , numberOfFrames = numberOfFrames
        , rotation = 0
        , pivot = ( 0, 0 )
        }


{-| the same with rotation
-}
animatedSpriteWithOptions :
    { o
        | texture : Maybe Texture
        , position : Float3
        , size : Float2
        , bottomLeft : Float2
        , topRight : Float2
        , rotation : Float
        , pivot : Float2
        , numberOfFrames : Int
        , duration : Float
    }
    -> Renderable
animatedSpriteWithOptions { texture, position, size, bottomLeft, topRight, duration, numberOfFrames, rotation, pivot } =
    let
        ( ( x, y, z ), ( w, h ), ( blx, bly ), ( trx, try ), ( px, py ) ) =
            ( position, size, bottomLeft, topRight, pivot )
    in
        case texture of
            Nothing ->
                shapeZ Rectangle { position = position, size = size, color = Color.grey }

            Just tex ->
                AnimatedSprite
                    { transform = makeTransform ( x, y, z ) (rotation) ( w, h ) ( px, py )
                    , texture = tex
                    , bottomLeft = vec2 blx bly
                    , topRight = vec2 trx try
                    , duration = duration
                    , numberOfFrames = numberOfFrames
                    }


{-|
Used for scrolling backgrounds.
This probably wont satisfy all possible needs for a scrolling background,
but it can give you something that looks nice quickly.
-}
parallaxScroll : { o | scrollSpeed : Float2, z : Float, tileWH : Float2, texture : Maybe Texture } -> Renderable
parallaxScroll { scrollSpeed, tileWH, texture, z } =
    parallaxScrollWithOptions { scrollSpeed = scrollSpeed, tileWH = tileWH, texture = texture, z = z, offset = ( 0.5, 0.5 ) }


{-|
Same but with an offset parameter that you can use to position the background.
-}
parallaxScrollWithOptions : { o | scrollSpeed : Float2, z : Float, tileWH : Float2, offset : Float2, texture : Maybe Texture } -> Renderable
parallaxScrollWithOptions { scrollSpeed, tileWH, texture, z, offset } =
    case texture of
        Nothing ->
            shapeZ Rectangle { position = ( 0, 0, z ), size = ( 1, 1 ), color = Color.grey }

        Just t ->
            ParallaxScroll
                { scrollSpeed = V2.fromTuple scrollSpeed
                , z = z
                , tileWH = V2.fromTuple tileWH
                , texture = t
                , offset = V2.fromTuple offset
                }


{-|
Just an alias for this crazy function, needed when you want to use customFragment
-}
type alias MakeUniformsFunc a =
    { cameraProj : Mat4, time : Float, transform : Mat4 }
    -> { a | cameraProj : Mat4, transform : Mat4 }


{-|
This allows you to write your own custom fragment shader.
The type signature may look terrifying,
but this is still easier than using veryCustom or using WebGL directly.
It handles the vertex shader for you, e.g. your object will appear at the expected location once rendered.

For the fragment shader, you have the `vec2 varying vcoord;` variable available,
which can be used to sample a texture (`texture2D(texture, vcoord);`)

The `MakeUniformsFunc` allows you to pass along any additional uniforms you may need.
In practice, this might look something like this:

    makeUniforms {cameraProj, transform, time} =
        {cameraProj=cameraProj, transform=transform, time=time, myUniform=someVector}

    render =
        customFragment makeUniforms { fragmentShader=frag, position=p, size=s, rotation=0, pivot=(0,0) }

    frag =
        [glsl|

    precision mediump float;

    varying vec2 vcoord;
    uniform vec2 myUniform;

    void main () {
      gl_FragColor = vcoord.yx + myUniform;
    }
    |]

Don't pass the time along if your shader doesn't need it.
-}
customFragment :
    MakeUniformsFunc u
    -> { b
        | fragmentShader :
            WebGL.Shader {} { u | cameraProj : Mat4, transform : Mat4 } { vcoord : Vec2 }
        , pivot : Float2
        , position : Float3
        , rotation : Float
        , size : Float2
       }
    -> Renderable
customFragment makeUniforms { fragmentShader, position, size, rotation, pivot } =
    let
        ( ( x, y, z ), ( w, h ), ( px, py ) ) =
            ( position, size, pivot )
    in
        Custom
            (\{ cameraProj, time } ->
                renderTransparent vertTexturedRect
                    fragmentShader
                    unitSquare
                    (makeUniforms
                        { transform = makeTransform ( x, y, z ) (rotation) ( w, h ) ( px, py )
                        , cameraProj = cameraProj
                        , time = time
                        }
                    )
            )


{-|
This allows you to specify your own attributes, vertex shader and fragment shader by using the WebGL library directly.
If you use this you have to calculate your transformations yourself. (You can use Shaders.makeTransform)

If you need a square as attributes, you can take the one from Game.TwoD.Shapes

    veryCustom (\{cameraProj, time} ->
        WebGL.entity vert frag Shapes.unitSquare
          { u_crazyFrog = frogTexture
          , transform = Shaders.makeTransform (x, y, z) 0 (2, 4) (0, 0)
          , camera = cameraProj
          }
    )
-}
veryCustom : ({ cameraProj : Mat4, time : Float } -> WebGL.Entity) -> Renderable
veryCustom =
    Custom
