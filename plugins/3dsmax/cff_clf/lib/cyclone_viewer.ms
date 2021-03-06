/*

*/

filein "max.ms"
filein "system.ms"
filein "utils.ms"
filein "math.ms"

struct cycloneViewerSettings
(
  texturesPath = "",
  isTextured = True,
  texFormat = "tf",
  lodIndex = 1,
  frameIndex = 0, 
  to3dsMaxSystem = True,
  isIntermediateFormat = False,
  isClockwizeOrder = True,
  startFrame = 0  
)

struct cycloneSceneViewer
(
  materials = #(),
  objects = #()
)

struct cycloneMeshViewer
(
  isIntermediateFormat = False,
  isClockwiseOrder = True, 
  fn create modelMesh materials: modelPos: modelScale:  =
  ( 
    local faceArray = #()   
    local vertArray = #()    

    for vert in modelMesh.vertexes do 
    (    
      if isIntermediateFormat then  
        append vertArray vert.coordinates            
      else
      (     
        local x = modelPos.x + (vert.coordinates.x * modelScale.x) / 32767.0 
        local y = modelPos.y + (vert.coordinates.y * modelScale.y) / 32767.0  
        local z = modelPos.z + (vert.coordinates.z * modelScale.z) / 32767.0   
        
        append vertArray [x, y, z] 
      )
    )      
    
    for face in modelMesh.faces do 
    (   
      face.indexes.x += 1     
      if isClockwiseOrder == False then
      (    
        face.indexes.y += 1 
        face.indexes.z += 1 
      ) 
      else
      (
        face.indexes.z += 1      
        face.indexes.y += 1       
      )
      
      append faceArray face.indexes
    ) 
      
    if materials != unsupplied then
    (
      tvertArray = #()
      
      for vert in modelMesh.vertexes do 
      (       
        if isIntermediateFormat then 
        (         
          local uvX = vert.uv.x         
          local uvY = vert.uv.y          
        )        
        else
        (
          local uvX = vert.uv.x/modelMesh.header.uvDelim    
          local uvY = vert.uv.y/modelMesh.header.uvDelim 
        )    
        
        append tvertArray [uvX, -uvY, 0]  
      )         
        
      msh = max.createTexturedMesh vertArray faceArray tvertArray \
        name:modelMesh.header.name
      
      max.material.addMaterialToMesh msh materials[modelMesh.header.textureIndex + 1]
    )
    else
      msh = max.createMesh vertArray faceArray name:modelMesh.header.name
    
    result = msh      
  )
)

struct cycloneAnimationViewer
(
  fn create msh frame startframe:0 transfCoordinates:true =
  (
    -- rads to degrees
    local angles = radToEuler frame.rotation
        
	transformMatrix = rotateMatByAngles	frame.rotation
          
    if transfCoordinates then
    (
      transMatrix = (matrix3 [1, 0, 0] [0, 0, 1] [0, -1, 0] [0, 0, 0]) 
      transformMatrix = transformMatrix*transMatrix
    )    
     
    max.controller.addKey msh.position.controller frame.time
    max.controller.addKey msh.rotation.controller frame.time 
    
    animate on
    (   
      at time (frame.time + startFrame) msh.position.controller.value = transformMatrix.translationpart 
      at time (frame.time + startFrame) msh.rotation.controller.value = transformMatrix.rotationpart
    )
  )
)

struct modelViewer
(
  model,
  scene = cycloneSceneViewer(),
  settings = cycloneViewerSettings(),
  meshViewer = cycloneMeshViewer(),  
  animationViewer = cycloneAnimationViewer(),  
  fn addMaterial name =
  (
    basename = fileUtils.getFileName name
    filepath = settings.texturesPath + "/" + basename + "." + settings.texFormat
    bitmapMaterial = max.material.createMaterialFromBitmap filepath basename

    if bitmapMaterial == undefined then
    (    
      standMat = max.material.createStandardMaterial true basename
      standMat.diffuseMap = max.material.createTextureMap name
      standMat.twoSided = True
      result = standMat
    )
    else
    ( bitmapMaterial.twoSided = True
      result = bitmapMaterial
    )  
  ),
  fn addMesh modelMesh mats: =
  (
    result = 
    (
      meshViewer.isIntermediateFormat = settings.isIntermediateFormat
      if mats == unsupplied then
        meshViewer.create modelMesh modelPos:model.header.origin \
          modelScale:model.header.scale
      else
        meshViewer.create modelMesh modelPos:model.header.origin \
          modelScale:model.header.scale materials:mats 
    )   
  ), 
  fn setAnimationFrame msh frame =
  (
    animationViewer.create msh frame startFrame:settings.startFrame \
      transfCoordinates:settings.to3dsMaxSystem
  ),  
  fn createScene redraw:true showProgress:true position: rotation: =
  (
    -- textures
    if settings.isTextured then 
    (
      max.sme.open()
      smeView = max.sme.createView "Materials"
      for i = 1 to model.header.textureCount do
      (
        mat = addMaterial model.textureList[i].name
        max.sme.createNode mat smeView [0, i*100]
        append scene.materials mat
      )  
      max.sme.close()   
    ) 
    
    if showProgress then progressStart "creating meshes"
    
    if settings.lodIndex == 0 then
    ( 
      startLodIndex = 1    
      lodCount = model.header.lodCount     
    )      
    else
    (
      if settings.lodIndex <= model.header.lodCount then
      (
        startLodIndex = settings.lodIndex    
        lodCount = settings.lodIndex  
      ) 
      else
      (
        startLodIndex = 1  
        lodCount = 1        
      )      
    )
    
    -- lods
    with undo off
    for i = startLodIndex to lodCount do
    (
      modelLod = model.modelLods[i]
      
      progress = (100.0/model.header.meshCount as float)          
    
      meshIndex = 1
    
      with redraw off        
      for modelMesh in modelLod.meshes do 
      (      
        if settings.isTextured then
          msh = addMesh modelMesh mats:scene.materials
        else
          msh = addMesh modelMesh
        
        if showProgress then progressUpdate (progress*meshIndex) 
        meshIndex += 1   
        
        if showProgress and getProgressCancel() then 
        (
          setProgressCancel true  
          exit        
        )  
                             
        if msh != undefined then
        (      			
          if position == unsupplied and rotation == unsupplied then
		  (
            rotAngles = mathFunction.radToEuler(rotation)
			mat = mathFunction.rotateMatByAngles rotAngles
			mat.row4 = position
			msh.transform = msh.transform*mat
          )		  
		
          append scene.objects msh       
          -- mesh animations
          if modelMesh.header.frameCount > 0 then
          (
            if settings.frameIndex == 0 then
            (        
              for frame in modelMesh.animationFrames do
              (
                if frame.time > animationRange.end then
                  max.animation.setLength frame.time 
                setAnimationFrame msh frame 
              )
            )
            else 
            (
              if settings.frameIndex <= modelMesh.header.frameCount then
                setAnimationFrame msh modelMesh.animationFrames[settings.frameIndex] 
              else        
                setAnimationFrame msh modelMesh.animationFrames[0]
            ) 
          )
          else
          (	  
            --convert coordinates to 3dsMax ones  			
            if settings.to3dsMaxSystem then
            (
              transMatrix = (matrix3 [-1, 0, 0] [0, 0, 1] [0, -1, 0] [0, 0, 0]) 
              msh.transform = msh.transform*transMatrix         
            )            
          )          
        )      
      )
      
      if showProgress then progressEnd()       
    ) 
    
    -- group model meshes
    max.nodes.createGroup scene.objects model.name opened:true
    
    if scene.objects.count > 0 and redraw then
    (
      select scene.objects[1]
      max zoomext sel  
      redrawViews()       
    ) 
  )  
)