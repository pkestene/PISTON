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

#ifndef RendererRender_H
#define RendererRender_H

#include <GL/glew.h>
#include <GL/gl.h>

#include <GL/glut.h>
#include <thrust/host_vector.h>
#include <thrust/functional.h>
#include <thrust/iterator/transform_iterator.h>
#include <thrust/iterator/discard_iterator.h>
#include <vtkSphereSource.h>
#include <vtkArrowSource.h>
#include <vtkPolyData.h>
#include <vtkCellArray.h>

#include <vtkCellData.h>
#include <vtkDoubleArray.h>
#include <vtkFloatArray.h>
#include <vtkPoints.h>
#include <vtkPolyData.h>
#include <vtkPolyDataNormals.h>
#include <vtkPointData.h>
#include <vtkSmartPointer.h>
#include <vtkXMLPolyDataReader.h>
#include <vtkTriangleFilter.h>
#include <vtkPolyDataNormals.h>
#include <vtkXMLImageDataReader.h>


#include <sys/time.h>
#include "piston/util/quaternion.h"

#include <piston/piston_math.h>
#include <piston/choose_container.h>

#include <piston/marching_cube.h>
#include <piston/util/tangle_field.h>

#include <piston/image3d.h>
#include <piston/vtk_image3d.h>

using namespace piston;
#define SPACE thrust::device_system_tag

#include <piston/image3d.h>
#include <piston/vtk_image3d.h>
#include <piston/render.h>

class RendererRender
{
public:
  RendererRender();
  void setZoomLevelPct(float pct);
  void display();
  void idle();
  void initGL(bool aAllowInterop);
  void cleanup();
  int read();
  void resetView();
  void screenShot(std::string fileName, unsigned int width, unsigned int height, bool includeAlpha = true );

  float3 center_pos;
  float3 camera_up;
  float cameraZ, cameraFOV, zoomLevelBase;
  int mouse_old_x, mouse_old_y;
  Quaternion qrot;
  bool includeInput;
  float isovalue;
  float isoMax, isoMin, isoInc;
  int rcnt;

  int mouse_buttons;
  float3 translate;
  float rotationMatrix[16];
  Quaternion qDefault;
  int grid_size, viewportWidth, viewportHeight;

  float maxValue, minValue;
  float zoomLevelPct, zoomLevelPctDefault;

  thrust::host_vector<float4>  inputVerticesHost;
  thrust::host_vector<float3>  inputNormalsHost;
  thrust::host_vector<float4>  inputColorsHost;
  thrust::device_vector<float4> inputVertices;
  thrust::device_vector<float3> inputNormals;
  thrust::device_vector<float4> inputColors;

  tangle_field<SPACE>* tangle;
  marching_cube<tangle_field<SPACE>, tangle_field<SPACE> > *isosurface;

  render<thrust::device_vector<float4>::iterator, thrust::device_vector<float3>::iterator, thrust::device_vector<float4>::iterator>* renders;

  vtkImageData *output;
  vtkXMLImageDataReader* reader;
  vtk_image3d<SPACE>* image;
  marching_cube<vtk_image3d<SPACE>, vtk_image3d<SPACE> >* isosurface2;

};

#endif
