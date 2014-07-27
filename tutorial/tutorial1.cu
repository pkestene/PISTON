/*
Copyright (c) 2012, Los Alamos National Security, LLC
All rights reserved.
Copyright 2012. Los Alamos National Security, LLC. This software was produced under U.S. Government contract DE-AC52-06NA25396 for Los Alamos National Laboratory (LANL),
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

Authors: Ollie Lo and Christopher Sewell, ollie@lanl.gov and csewell@lanl.gov
*/

#ifdef __APPLE__
  #include <GL/glew.h>
  #include <OpenGL/OpenGL.h>
  #include <GLUT/glut.h>
#else
  #include <GL/glew.h>
  #include <GL/glut.h>
  #include <GL/gl.h>
#endif

#include <QtGui>
#include <QObject>

#ifdef USE_INTEROP
#include <cuda_gl_interop.h>
#endif

#include <piston/piston_math.h> 
#include <piston/choose_container.h>

#define SPACE thrust::device_space_tag
using namespace piston;

#include <piston/implicit_function.h>
#include <piston/image3d.h>
#include <piston/marching_cube.h>
#include <piston/util/tangle_field.h>
#include <piston/util/plane_field.h>
#include <piston/util/sphere_field.h>
#include <piston/threshold_geometry.h>

#include <sys/time.h>
#include <stdio.h>
#include <math.h>

#include "glwindow.h"


//==========================================================================
/*! 
    Variable declarations
*/
//==========================================================================

//! Variables for timing the framerate
struct timeval begin, end, diff;
int frameCount;

//! Tangle field and marching cube operator
tangle_field<SPACE>* tangle;
marching_cube<tangle_field<SPACE>, tangle_field<SPACE> > *isosurface;

//! Vertices, normals, and colors for output
thrust::host_vector<float4> vertices;
thrust::host_vector<float3> normals;
thrust::host_vector<float4> colors;

//! Camera and UI variables
float cameraFOV;
int gridSize;
bool wireframe;
float minIsovalue, maxIsovalue;

//! Vertex buffer objects used by CUDA interop
#ifdef USE_INTEROP
  GLuint vboBuffers[4];  struct cudaGraphicsResource* vboResources[4];
#endif


//==========================================================================
/*! 
    Constructor for GLWindow class

    \fn	GLWindow::GLWindow
*/
//==========================================================================
GLWindow::GLWindow(QWidget *parent)
    : QGLWidget(QGLFormat(QGL::SampleBuffers), parent)
{
    // Start the QT callback timer
    setFocusPolicy(Qt::StrongFocus);
    timer = new QTimer(this);
    connect(timer, SIGNAL(timeout()), this, SLOT(updateGL()));
    timer->start(1);
}


//==========================================================================
/*! 
    Create the tangle field and the marching cubes operator

    \fn	GLWindow::initializeGL
*/
//==========================================================================
void GLWindow::initializeGL()
{
    // Initialize camera and UI variables
    qrot.set(0,0,0,1);
    frameCount = 0;
    gridSize = 64;
    cameraFOV = 60.0f;
    minIsovalue = 31.0f;
    maxIsovalue = 500.0f;
    wireframe = false;

    // Set up basic OpenGL state and lighting
    glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
    glEnable(GL_DEPTH_TEST);
    glShadeModel(GL_SMOOTH);
    float white[] = { 0.8, 0.8, 0.8, 1.0 };
    float black[] = { 0.0, 0.0, 0.0, 1.0 };
    float lightPos[] = { 0.0, 0.0, gridSize*1.5, 1.0 };
    glLightfv(GL_LIGHT0, GL_AMBIENT, white);
    glLightfv(GL_LIGHT0, GL_DIFFUSE, white);
    glLightfv(GL_LIGHT0, GL_SPECULAR, black);
    glLightfv(GL_LIGHT0, GL_POSITION, lightPos);
    glLightModeli(GL_LIGHT_MODEL_TWO_SIDE, 1);
    glEnable(GL_LIGHTING);
    glEnable(GL_LIGHT0);
    glEnable(GL_NORMALIZE);
    glColorMaterial(GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE);
    glEnable(GL_COLOR_MATERIAL);

    // Initialize CUDA interop if it is being used
    #ifdef USE_INTEROP
      glewInit();
      cudaGLSetGLDevice(0);
    #endif

    // Create the tangle field and marching cube operator instances
    tangle = new tangle_field<SPACE>(gridSize, gridSize, gridSize);
    isosurface = new marching_cube<tangle_field<SPACE>,  tangle_field<SPACE> >(*tangle, *tangle, 0.2f);

    // Compute the isosurface of the tangle field 
    (*isosurface)();

    // If using interop, generate the vertex buffer objects to be shared between CUDA and OpenGL
    #ifdef USE_INTEROP
      int numPoints = thrust::distance(isosurface->vertices_begin(), isosurface->vertices_end());
      glGenBuffers(3, vboBuffers);
      for (int i=0; i<3; i++)
      {
        unsigned int bufferSize = (i == 2) ? numPoints*sizeof(float3) : numPoints*sizeof(float4);
        glBindBuffer(GL_ARRAY_BUFFER, vboBuffers[i]);
        glBufferData(GL_ARRAY_BUFFER, bufferSize, 0, GL_DYNAMIC_DRAW);
      }
      glBindBuffer(GL_ARRAY_BUFFER, 0);
      for (int i=0; i<3; i++)
      {
        cudaGraphicsGLRegisterBuffer(&(vboResources[i]), vboBuffers[i], cudaGraphicsMapFlagsWriteDiscard);   
        isosurface->vboResources[i] = vboResources[i];
      }
      isosurface->minIso = minIsovalue;  isosurface->maxIso = maxIsovalue;  isosurface->useInterop = true;  isosurface->vboSize = numPoints;
    #endif

    // Enable OpenGL state for vertex, normal, and color arrays
    glEnableClientState(GL_VERTEX_ARRAY);
    glEnableClientState(GL_NORMAL_ARRAY);
    glEnableClientState(GL_COLOR_ARRAY);
}


//==========================================================================
/*! 
    Update the graphics

    \fn	GLWindow::paintGL
*/
//==========================================================================
void GLWindow::paintGL()
{
    // Stop the QT callback timer
    timer->stop();

    // Start timing this interval
    if (frameCount == 0) gettimeofday(&begin, 0);

    // Set up the OpenGL state
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    if (wireframe) glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
    else glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);

    // Set up the projection and modelview matrices for the view
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    gluPerspective(cameraFOV, 1.0f, 1.0f, gridSize*4.0f);
    glMatrixMode(GL_MODELVIEW);
    glPushMatrix();
    glLoadIdentity();
    gluLookAt(0.0f, 0.0f, 4.0f, 0.0f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f);

    // Set up the current rotation and translation
    qrot.getRotMat(rotationMatrix);
    glMultMatrixf(rotationMatrix);  

    // Compute the isosurface of the tangle field
    (*isosurface)();

    // If using interop, render the vertex buffer objects; otherwise, render the arrays
    #ifdef USE_INTEROP
      glBindBuffer(GL_ARRAY_BUFFER, vboBuffers[0]);
      glVertexPointer(4, GL_FLOAT, 0, 0);

      glBindBuffer(GL_ARRAY_BUFFER, vboBuffers[2]);
      glNormalPointer(GL_FLOAT, 0, 0);

      glBindBuffer(GL_ARRAY_BUFFER, vboBuffers[1]);
      glColorPointer(4, GL_FLOAT, 0, 0);

      glDrawArrays(GL_TRIANGLES, 0, isosurface->vboSize);
    #else
      vertices.assign(isosurface->vertices_begin(), isosurface->vertices_end());
      normals.assign(isosurface->normals_begin(), isosurface->normals_end());
      colors.assign(thrust::make_transform_iterator(isosurface->scalars_begin(), color_map<float>(31.0f, 500.0f)),
                    thrust::make_transform_iterator(isosurface->scalars_end(), color_map<float>(31.0f, 500.0f)));
      glColorPointer(4, GL_FLOAT, 0, &colors[0]);
      glNormalPointer(GL_FLOAT, 0, &normals[0]);
      glVertexPointer(4, GL_FLOAT, 0, &vertices[0]);
      glDrawArrays(GL_TRIANGLES, 0, vertices.size());
    #endif

    // Pop this OpenGL view matrix
    glPopMatrix();

    // Periodically output the framerate
    gettimeofday(&end, 0);
    timersub(&end, &begin, &diff);
    frameCount++;
    float seconds = diff.tv_sec + 1.0E-6*diff.tv_usec;
    if (seconds > 0.5f)
    {
      char title[256];
      sprintf(title, "Marching Cube, fps: %2.2f", float(frameCount)/seconds);
      std::cout << title << std::endl;
      seconds = 0.0f;
      frameCount = 0;
    }

    // Restart the QT callback timer
    timer->start(1);
}


//==========================================================================
/*! 
    Handle window resize event

    \fn	GLWindow::resizeGL
*/
//==========================================================================
void GLWindow::resizeGL(int width, int height)
{
    glViewport(0, 0, width, height);
}


//==========================================================================
/*! 
    Handle mouse press event

    \fn	GLWindow::mousePressEvent
*/
//==========================================================================
void GLWindow::mousePressEvent(QMouseEvent *event)
{
    lastPos = event->pos();
}


//==========================================================================
/*! 
    Handle mouse move event to rotate, translate, or zoom

    \fn	GLWindow::mouseMoveEvent
*/
//==========================================================================
void GLWindow::mouseMoveEvent(QMouseEvent *event)
{
    int dx = event->x() - lastPos.x();
    int dy = event->y() - lastPos.y();

    // Rotate or zoom the view
    if (event->buttons() & Qt::LeftButton)
    {
      Quaternion newRotX;
      newRotX.setEulerAngles(-0.2f*dx*3.14159f/180.0f, 0.0f, 0.0f);
      qrot.mul(newRotX);

      Quaternion newRotY;
      newRotY.setEulerAngles(0.0f, 0.0f, -0.2f*dy*3.14159f/180.0f);
      qrot.mul(newRotY);
    }
    else if (event->buttons() & Qt::RightButton)
    {
      cameraFOV += dy/20.0f;
    }
    lastPos = event->pos();
}


//==========================================================================
/*! 
    Handle keyboard input event

    \fn	GLWindow::keyPressEvent
*/
//==========================================================================
void GLWindow::keyPressEvent(QKeyEvent *event)
{
   // Toggle wireframe mode
   if ((event->key() == 'w') || (event->key() == 'W'))
       wireframe = !wireframe;
}


