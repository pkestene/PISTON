/*
 * eddy.cu
 *
 *  Created on: Oct 21, 2011
 *      Author: ollie
 */
#include <sys/time.h>

#include <GL/glew.h>
#include <GL/gl.h>
#include <GL/glut.h>

#include <cuda_gl_interop.h>

#include <vtkXMLImageDataReader.h>

#include <piston/threshold_geometry.h>
#include <piston/vtk_image3d.h>

static const int GRID_SIZE = 256;

using namespace piston;

#define SPACE thrust::detail::default_device_space_tag
//#define SPACE thrust::host_space


int mouse_old_x, mouse_old_y;
int mouse_buttons = 0;
float3 rotate = make_float3(0, 0, 0.0);
float3 translate = make_float3(0.0, 0.0, 0.0);

void mouse(int button, int state, int x, int y)
{
    if (state == GLUT_DOWN) {
	mouse_buttons |= 1<<button;
    } else if (state == GLUT_UP) {
	mouse_buttons = 0;
    }

    mouse_old_x = x;
    mouse_old_y = y;
    glutPostRedisplay();
}

void motion(int x, int y)
{
    float dx = x - mouse_old_x;
    float dy = y - mouse_old_y;

    if (mouse_buttons==1) {
	rotate.x += dy * 0.2;
	rotate.y += dx * 0.2;
    } else if (mouse_buttons==2) {
	translate.x += dx * 0.01;
	translate.y -= dy * 0.01;
    } else if (mouse_buttons==4) {
	translate.z += dy * 0.1;
    }

    mouse_old_x = x;
    mouse_old_y = y;
    glutPostRedisplay();
}

bool wireframe = false;
bool animate = true;
void keyboard( unsigned char key, int x, int y )
{
    switch (key) {
    case 'w':
	wireframe = !wireframe;
	break;
    case 'a':
	animate = !animate;
	break;
    }
}

threshold_geometry<vtk_image3d<int, float, SPACE> > *threshold_p;
GLuint quads_vbo[2];
struct cudaGraphicsResource *quads_pos_res, *quads_color_res;
unsigned int buffer_size;

void create_vbo()
{
    glGenBuffers(2, quads_vbo);

    int error;
    std::cout << "number of vertices: " << thrust::distance(threshold_p->vertices_begin(), threshold_p->vertices_end()) << std::endl;
    buffer_size = thrust::distance(threshold_p->vertices_begin(), threshold_p->vertices_end())* sizeof(float4);

    // initialize vertex buffer object
    glBindBuffer(GL_ARRAY_BUFFER, quads_vbo[0]);
    glBufferData(GL_ARRAY_BUFFER, buffer_size, 0, GL_DYNAMIC_DRAW);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    // register this buffer object with CUDA
    if ((error = cudaGraphicsGLRegisterBuffer(&quads_pos_res, quads_vbo[0],
                                              cudaGraphicsMapFlagsWriteDiscard)) != cudaSuccess) {
	std::cout << "register pos buffer cuda error: " << error << "\n";
    }

    // initialize color buffer object
    glBindBuffer(GL_ARRAY_BUFFER, quads_vbo[1]);
    glBufferData(GL_ARRAY_BUFFER, buffer_size, 0, GL_DYNAMIC_DRAW);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    // register this buffer object with CUDA
    if (cudaGraphicsGLRegisterBuffer(&quads_color_res, quads_vbo[1],
                                     cudaGraphicsMapFlagsWriteDiscard) != cudaSuccess) {
	std::cout << "register color buffer cuda error: " << error << "\n";
    }
}

struct timeval begin, end, diff;
int frame_count = 0;

void display()
{
    if (frame_count == 0) {
	gettimeofday(&begin, 0);
    }

    (*threshold_p)();

#if 1
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    if (wireframe) {
	glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
    } else {
//	glPolygonMode(GL_BACK, GL_FILL);
//	glPolygonMode(GL_FRONT, GL_FILL);
	glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
    }

    // set view matrix for 3D scene
    glMatrixMode(GL_MODELVIEW);
    glPopMatrix();
    glPushMatrix();

    glRotatef(rotate.x, 1.0, 0.0, 0.0);
    glRotatef(rotate.y, 0.0, 1.0, 0.0);
    glTranslatef(-(GRID_SIZE-1)/2, -(GRID_SIZE-1)/2, -(GRID_SIZE-1)/2);
    glTranslatef(translate.x, translate.y, translate.z);

    float4 *raw_ptr;
    size_t num_bytes;

    cudaGraphicsMapResources(1, &quads_pos_res, 0);
    cudaGraphicsResourceGetMappedPointer((void**)&raw_ptr, &num_bytes, quads_pos_res);
    thrust::copy(thrust::make_transform_iterator(threshold_p->vertices_begin(), tuple2float4()),
                 thrust::make_transform_iterator(threshold_p->vertices_end(),   tuple2float4()),
                 thrust::device_ptr<float4>(raw_ptr));
    cudaGraphicsUnmapResources(1, &quads_pos_res, 0);
    glBindBuffer(GL_ARRAY_BUFFER, quads_vbo[0]);
    glVertexPointer(4, GL_FLOAT, 0, 0);

    cudaGraphicsMapResources(1, &quads_color_res, 0);
    cudaGraphicsResourceGetMappedPointer((void**)&raw_ptr, &num_bytes, quads_color_res);
    thrust::transform(threshold_p->scalars_begin(), threshold_p->scalars_end(),
                      thrust::device_ptr<float4>(raw_ptr),
                      color_map<float>(200.0f, 400.0f));
    cudaGraphicsUnmapResources(1, &quads_color_res, 0);
    glBindBuffer(GL_ARRAY_BUFFER, quads_vbo[1]);
    glColorPointer(4, GL_FLOAT, 0, 0);


    glDrawArrays(GL_QUADS, 0, buffer_size/sizeof(float4));

    glutSwapBuffers();
#endif

    gettimeofday(&end, 0);
    timersub(&end, &begin, &diff);
    frame_count++;
    float seconds = diff.tv_sec + 1.0E-6*diff.tv_usec;
    if (seconds > 0.5f) {
	char title[256];
	sprintf(title, "Threshold, fps: %2.2f", float(frame_count)/seconds);
	glutSetWindowTitle(title);
	seconds = 0.0f;
	frame_count = 0;
    }
}

void idle()
{
    if (animate) {
//	isovalue += delta;
//	if (isovalue > maxiso)
//	    delta = -0.05;
//	if (isovalue < miniso)
//	    delta = 0.05;
//	glutPostRedisplay();
    }
    glutPostRedisplay();
}

void initGL(int argc, char **argv)
{
    glutInit(&argc, argv);
    glutInitDisplayMode(GLUT_DOUBLE | GLUT_RGB | GLUT_DEPTH);
    glutInitWindowSize(800, 800);
    glutCreateWindow("Ocean Eddy");

    glewInit();

    glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
    glEnable(GL_DEPTH_TEST);
    glShadeModel(GL_SMOOTH);

    // good old-fashioned fixed function lighting
    float white[] = { 0.8, 0.8, 0.8, 1.0 };
    float lightPos[] = { 100.0, 100.0, -100.0, 1.0 };

    glMaterialfv(GL_FRONT_AND_BACK, GL_SPECULAR, white);
    glMaterialf(GL_FRONT_AND_BACK, GL_SHININESS, 100);

    glLightfv(GL_LIGHT0, GL_AMBIENT, white);
    glLightfv(GL_LIGHT0, GL_DIFFUSE, white);
    glLightfv(GL_LIGHT0, GL_SPECULAR, white);
    glLightfv(GL_LIGHT0, GL_POSITION, lightPos);

    glLightModeli(GL_LIGHT_MODEL_LOCAL_VIEWER, 1);
//    glLightModeli(GL_LIGHT_MODEL_TWO_SIDE, 1);

    glEnable(GL_LIGHTING);
    glEnable(GL_LIGHT0);
    glEnable(GL_COLOR_MATERIAL);

    /* Setup the view of the cube. */
    glMatrixMode(GL_PROJECTION);
    gluPerspective( /* field of view in degree */ 60.0,
                    /* aspect ratio */ 1.0,
                    /* Z near */ 1.0, /* Z far */ GRID_SIZE*4.0);

    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    gluLookAt(0.0, 0.0, GRID_SIZE*1.5,  /* eye is at (0,0, 1.5*GRID_SIZE) */
              0.0, 0.0, 0.0,		/* center is at (0,0,0) */
              0.0, 1.0, 0.0);		/* up is in positive Y direction */
    glPushMatrix();

    // enable vertex and normal arrays
    glEnableClientState(GL_VERTEX_ARRAY);
//    glEnableClientState(GL_NORMAL_ARRAY);
    glEnableClientState(GL_COLOR_ARRAY);
}

int main(int argc, char **argv)
{
    initGL(argc, argv);
    cudaGLSetGLDevice(0);

    vtkXMLImageDataReader *reader = vtkXMLImageDataReader::New();
    reader->SetFileName(argv[1]);
    reader->Update();

    vtkImageData *vtk_image = reader->GetOutput();

    vtk_image3d<int, float, SPACE> image(vtk_image);
    threshold_geometry<vtk_image3d<int, float, SPACE> > threshold(image, 50.0f, 400.0f);
    threshold();
    threshold_p = &threshold;

    create_vbo();

    glutDisplayFunc(display);
    glutKeyboardFunc(keyboard);
    glutMouseFunc(mouse);
    glutMotionFunc(motion);
    glutIdleFunc(idle);
    glutMainLoop();

    return 0;
}
