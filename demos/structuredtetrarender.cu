/*
Copyright (c) 2011, Los Alamos National Security, LLC
All rights reserved.
Copyright 2011. Los Alamos National Security, LLC. This software was produced under U.S. Government contract DE-AC52-06NA25396 for Los Alamos National Laboratory (LANL),
which is operated by Los Alamos National Security, LLC for the U.S. Department of Energy. The U.S. Government has rights to use, reproduce, and distribute this software.

NEITHER THE GOVERNMENT NOR LOS ALAMOS NATIONAL SECURITY, LLC MAKES ANY WARRANTY, EXPRESS OR IMPLIED, OR ASSUMES ANY LIABILITY FOR THE USE OF THIS SOFTWARE.

If software is modified to produce derivative works, such modified software should be clearly marked, so as not to confuse it with the version available from LANL.

Additionally, redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
·         Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
·         Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other
          materials provided with the distribution.
·         Neither the name of Los Alamos National Security, LLC, Los Alamos National Laboratory, LANL, the U.S. Government, nor the names of its contributors may be used
          to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY LOS ALAMOS NATIONAL SECURITY, LLC AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL LOS ALAMOS NATIONAL SECURITY, LLC OR CONTRIBUTORS BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA,
OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#include <thrust/host_vector.h>
#include <thrust/functional.h>
#include <thrust/iterator/transform_iterator.h>
#include <thrust/iterator/discard_iterator.h>
#include <algorithm>
#include <fstream>
#include <iostream>
#include <sstream>
#include <float.h>

#include "structuredtetrarender.h"

#define STRINGIZE(x) #x
#define STRINGIZE_VALUE_OF(x) STRINGIZE(x)

#define TETRA_BUFFER_SIZE 12000000


TetraRender::TetraRender()
{
    mouse_buttons = 0;
    translate = make_float3(0.0, 0.0, 0.0);
}


void TetraRender::setZoomLevelPct(float pct)
{
    if (pct > 1.0) pct = 1.0;  if (pct < 0.0) pct = 0.0;
    zoomLevelPct = pct;
    cameraFOV = 0.0 + zoomLevelBase*pct;
}


void TetraRender::resetView()
{
    qrot.set(qDefault.x, qDefault.y, qDefault.z, qDefault.w);
    zoomLevelPct = zoomLevelPctDefault;
    cameraFOV = 0.0 + zoomLevelBase*zoomLevelPct;
}


void TetraRender::display()
{
    if (true)
    {
#ifdef USE_INTEROP

      if (useInterop)
      {
        for (int i=0; i<4; i++) isosurface->vboResources[i] = vboResources[i];
        isosurface->minIso = minValue;  isosurface->maxIso = maxValue;
      }
#endif

      isosurface->set_isovalue(200.0f);
      ((*isosurface)());

      if (!useInterop)
      {
    	normals.assign(isosurface->normals_begin(), isosurface->normals_end());
    	vertices.assign(isosurface->vertices_begin(), isosurface->vertices_end());
    	colors.assign(thrust::make_transform_iterator(isosurface->scalars_begin(), color_map<float>(minValue, maxValue)),
    	              thrust::make_transform_iterator(isosurface->scalars_end(), color_map<float>(minValue, maxValue)));
      }
    }

    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    glPolygonMode(GL_FRONT, GL_FILL);
    glPolygonMode(GL_BACK, GL_LINE);

    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    gluPerspective(cameraFOV, 2.0, 0.01, 100.0);

    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    gluLookAt(centerPos.x, -5.0f*centerPos.y, centerPos.z, centerPos.x, 0, centerPos.z, cameraUp.x, cameraUp.y, cameraUp.z); 
    glPushMatrix();

    qrot.getRotMat(rotationMatrix);
    float3 offset = matrixMul(rotationMatrix, centerPos);

    glMultMatrixf(rotationMatrix);
    glTranslatef(offset.x-centerPos.x, offset.y-centerPos.y, offset.z-centerPos.z);

    glEnableClientState(GL_VERTEX_ARRAY);
    glEnableClientState(GL_COLOR_ARRAY);
    glEnableClientState(GL_NORMAL_ARRAY);

#ifdef USE_INTEROP
    if (useInterop)
    {
      glBindBuffer(GL_ARRAY_BUFFER, vboBuffers[0]);
      glVertexPointer(4, GL_FLOAT, 0, 0);
      glBindBuffer(GL_ARRAY_BUFFER, vboBuffers[1]);
      glColorPointer(4, GL_FLOAT, 0, 0);
      glBindBuffer(GL_ARRAY_BUFFER, vboBuffers[2]);
      glNormalPointer(GL_FLOAT, 0, 0);
      glDrawArrays(GL_TRIANGLES, 0, isosurface->num_total_vertices);
      glBindBuffer(GL_ARRAY_BUFFER, 0);
    }
    else
#endif
    {
      if (showIso)
      {
        glNormalPointer(GL_FLOAT, 0, &normals[0]);
        glColorPointer(4, GL_FLOAT, 0, &colors[0]);
        glVertexPointer(4, GL_FLOAT, 0, &vertices[0]);
        glDrawArrays(GL_TRIANGLES, 0, vertices.size());
      }
    }

    glDisableClientState(GL_VERTEX_ARRAY);
    glDisableClientState(GL_COLOR_ARRAY);
    glDisableClientState(GL_NORMAL_ARRAY);

    glPopMatrix();
}


void TetraRender::cleanup()
{
#ifdef USE_INTEROP
    if (useInterop)
    {
      printf("Deleting VBO\n");
      if (vboBuffers[0])
      {
        for (int i=0; i<4; i++) cudaGraphicsUnregisterResource(vboResources[i]);
	for (int i=0; i<4; i++)
	{
	  glBindBuffer(1, vboBuffers[i]);
	  glDeleteBuffers(1, &(vboBuffers[i]));
	  vboBuffers[i] = 0;
	}
      }
    }
    else
#endif
    {
      vertices.clear(); normals.clear(); colors.clear();
    }
}


void TetraRender::initGL(bool aAllowInterop)
{
#ifdef USE_INTEROP
    useInterop = aAllowInterop;
#else
    useInterop = false;
#endif

    glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
    glEnable(GL_DEPTH_TEST);
    glShadeModel(GL_SMOOTH);

    float white[] = { 0.5, 0.5, 0.5, 1.0 };
    float black[] = { 0.0, 0.0, 0.0, 1.0 };
    float lightPos[] = { 0.0, 0.0, 10.0, 1.0 };
    glMaterialfv(GL_FRONT_AND_BACK, GL_SPECULAR, white);
    glMaterialf(GL_FRONT_AND_BACK, GL_SHININESS, 100);
    glLightfv(GL_LIGHT0, GL_AMBIENT, white);
    glLightfv(GL_LIGHT0, GL_DIFFUSE, white);
    glLightfv(GL_LIGHT0, GL_SPECULAR, black);
    glLightfv(GL_LIGHT0, GL_POSITION, lightPos);

    glLightModeli(GL_LIGHT_MODEL_LOCAL_VIEWER, 1);
    glLightModeli(GL_LIGHT_MODEL_TWO_SIDE, 1);

    glEnable(GL_LIGHTING);
    glEnable(GL_LIGHT0);
    glEnable(GL_NORMALIZE);
    glEnable(GL_COLOR_MATERIAL);

#ifdef USE_INTEROP
    if (useInterop)
    {
      glewInit();
      cudaGLSetGLDevice(0);

      // initialize contour buffer objects
      glGenBuffers(4, vboBuffers);
      for (int i=0; i<3; i++)
      {
        unsigned int buffer_size = (i == 2) ? TETRA_BUFFER_SIZE*sizeof(float3) : TETRA_BUFFER_SIZE*sizeof(float4);
        glBindBuffer(GL_ARRAY_BUFFER, vboBuffers[i]);
        glBufferData(GL_ARRAY_BUFFER, buffer_size, 0, GL_DYNAMIC_DRAW);
      }
      glBindBuffer(GL_ARRAY_BUFFER, vboBuffers[3]);
      glBufferData(GL_ARRAY_BUFFER, TETRA_BUFFER_SIZE*sizeof(uint3), 0, GL_DYNAMIC_DRAW);

      glBindBuffer(GL_ARRAY_BUFFER, 0);
      for (int i=0; i<4; i++) cudaGraphicsGLRegisterBuffer(&(vboResources[i]), vboBuffers[i], cudaGraphicsMapFlagsWriteDiscard);
    }
#endif

    src = vtkRTAnalyticSource::New();
    src->SetWholeExtent(-GRID_SIZE, GRID_SIZE, -GRID_SIZE, GRID_SIZE, -GRID_SIZE, GRID_SIZE);
    src->Update();

    image = new vtk_image3d<SPACE>(src->GetOutput());

    // get max and min of 3D scalars
    float min_iso = *thrust::min_element(image->point_data_begin(), image->point_data_end());
    float max_iso = *thrust::max_element(image->point_data_begin(), image->point_data_end());
    std::cout << "Range " << min_iso << " " << max_iso << std::endl;

    tetra = new tetra_source(*image);

    isosurface = new marching_tetrahedron<tetra_source, tetra_source>(*tetra, *tetra, 160.0f);

    showIso = true;
    
    isosurface->useInterop = useInterop;
    zoomLevelBase = cameraFOV = 40.0; cameraZ = 2.0; zoomLevelPct = zoomLevelPctDefault = 0.5;
    centerPos = make_float3(GRID_SIZE, GRID_SIZE, GRID_SIZE);
    cameraFOV = zoomLevelBase*zoomLevelPct;  cameraUp = make_float3(0,0,1);
}




